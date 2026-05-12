# =============================================================================
# modules/cloud_run/main.tf — Cloud Run Services
# =============================================================================
# CONCEPT: Cloud Run in Terraform
# Each Cloud Run service is a containerized application that GCP manages.
# You provide a Docker image and configuration; GCP handles scaling,
# load balancing, TLS, and health checks.
#
# Two services with different scaling strategies:
#
# INGESTION (serverless):
#   min_instance_count = 0  → scales to zero when idle = $0 cost
#   Called at most a few times per day (when user uploads a book)
#   Cold start (3-8s) is acceptable — user is already waiting
#
# CHAT (always-on):
#   min_instance_count = 1  → one instance always running = no cold start
#   Called on every user message — latency is critical
#   Cost: ~$5-8/month for one small instance kept alive
# =============================================================================

# ---------------------------------------------------------------------------
# Ingestion Service
# ---------------------------------------------------------------------------

resource "google_cloud_run_v2_service" "ingestion" {
  name     = "alexandria-ingestion-${var.environment}"
  location = var.region
  project  = var.project_id

  # CONCEPT: ingress = INTERNAL_AND_CLOUD_LOAD_BALANCING
  # Only allows traffic from within GCP and via Cloud Load Balancing.
  # Direct internet access is blocked. The NeoReader app calls this via
  # the public URL that Cloud Run provides (which routes through GCP's edge).
  # Change to ALL_TRAFFIC if you need direct public access.
  ingress = "INGRESS_TRAFFIC_ALL"

  template {
    # Service account with least-privilege permissions
    service_account = var.ingestion_service_account

    scaling {
      min_instance_count = 0   # scales to zero — serverless
      max_instance_count = 10  # max concurrent instances
    }

    # CONCEPT: Timeout for epub processing
    # A large epub (500+ pages) can take 60+ seconds to process.
    # Default Cloud Run timeout is 60s — increase to 300s.
    timeout = "300s"

    containers {
      image = var.ingestion_image

      resources {
        limits = {
          cpu    = "2"      # 2 vCPU — embedder.py uses batch calls but
          memory = "2Gi"    # 2GB RAM — ebooklib can use significant memory
        }                   # for large epubs
        cpu_idle = false    # release CPU when not processing a request
      }

      # Environment variables — non-sensitive configuration
      env {
        name  = "GOOGLE_CLOUD_PROJECT"
        value = var.project_id
      }
      env {
        name  = "FIREBASE_STORAGE_BUCKET"
        value = var.storage_bucket
      }
      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }
      env {
        name  = "CHUNK_SIZE"
        value = tostring(var.chunk_size)
      }
      env {
        name  = "CHUNK_OVERLAP"
        value = tostring(var.chunk_overlap)
      }
      env {
        name  = "EMBEDDING_MODEL"
        value = "text-embedding-004"
      }

      # CONCEPT: Secret Manager for sensitive values
      # API keys are stored in Secret Manager, not in environment variables.
      # Cloud Run pulls them at startup — they never appear in logs or state files.
      env {
        name = "OPENAI_API_KEY"
        value_source {
          secret_key_ref {
            secret  = var.openai_api_key_secret
            version = "latest"
          }
        }
      }
    }
  }

  depends_on = [var.ingestion_service_account]
}

# Allow unauthenticated calls to ingestion service
# The NeoReader app calls POST /ingest without a GCP service account.
# Application-level auth (Firebase Auth token) is handled in the FastAPI code.
resource "google_cloud_run_v2_service_iam_member" "ingestion_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.ingestion.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ---------------------------------------------------------------------------
# Chat Service
# ---------------------------------------------------------------------------

resource "google_cloud_run_v2_service" "chat" {
  name     = "alexandria-chat-${var.environment}"
  location = var.region
  project  = var.project_id

  ingress = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = var.chat_service_account

    scaling {
      min_instance_count = 1   # ALWAYS ON — eliminates cold start for chat
      max_instance_count = 5   # scale up if multiple users chat simultaneously
    }

    # SSE connections stay open while Gemini streams the response.
    # 120s covers even long responses from large books.
    timeout = "120s"

    containers {
      image = var.chat_image

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"  # chat service is lightweight — just orchestrates calls
        }
        # CONCEPT: cpu_idle = true for always-on services
        # When min_instance_count=1, the instance is always running.
        # cpu_idle=true means CPU is throttled between requests (cheaper).
        # cpu_idle=false means full CPU always allocated (more expensive).
        cpu_idle = true
      }

      env {
        name  = "GOOGLE_CLOUD_PROJECT"
        value = var.project_id
      }
      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }
      env {
        name  = "RETRIEVAL_TOP_K"
        value = tostring(var.retrieval_top_k)
      }
      env {
        name  = "EMBEDDING_MODEL"
        value = "text-embedding-004"
      }
      env {
        name  = "GEMINI_MODEL"
        value = "gemini-1.5-flash"
      }

      env {
        name = "GEMINI_API_KEY"
        value_source {
          secret_key_ref {
            secret  = var.gemini_api_key_secret
            version = "latest"
          }
        }
      }
    }
  }
}

# Allow unauthenticated calls to chat service
resource "google_cloud_run_v2_service_iam_member" "chat_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.chat.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
