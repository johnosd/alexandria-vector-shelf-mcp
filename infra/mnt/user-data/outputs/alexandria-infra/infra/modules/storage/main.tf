# =============================================================================
# modules/storage/main.tf — Firebase Storage Bucket
# =============================================================================
# CONCEPT: Firebase Storage is built on top of Google Cloud Storage (GCS).
# The bucket created here is the same bucket you see in the Firebase console
# under Storage. Terraform manages it via the google_storage_bucket resource.
#
# Security note: the bucket is PRIVATE. The app uploads files using
# Firebase SDK (which uses Firebase Auth tokens). The Cloud Run ingestion
# service downloads files using its service account (IAM).
# No file is ever publicly accessible.
# =============================================================================

resource "google_storage_bucket" "epubs" {
  name     = "${var.project_id}-epubs-${var.environment}"
  location = var.region
  project  = var.project_id

  # CONCEPT: Uniform bucket-level access
  # Disables per-object ACLs — all access is controlled via IAM only.
  # This is the modern, recommended approach. Simpler and more secure.
  uniform_bucket_level_access = true

  # Prevent accidental deletion of the bucket (and all epubs inside it)
  # Change to false only when you intentionally want to destroy everything
  force_destroy = var.environment == "dev" ? true : false

  # Lifecycle rule: delete epub files older than 90 days
  # After ingestion, the epub is processed and chunks are in Firestore.
  # The original file is kept for 90 days for re-ingestion if needed.
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }

  # Enable versioning in production to recover accidentally deleted files
  versioning {
    enabled = var.environment == "prod"
  }

  labels = {
    environment = var.environment
    project     = "alexandria"
    managed-by  = "terraform"
  }
}

# CORS configuration — allows the NeoReader app (running on mobile/web)
# to upload files directly to the bucket from the client side
resource "google_storage_bucket_iam_member" "firebase_auth_upload" {
  bucket = google_storage_bucket.epubs.name
  role   = "roles/storage.objectCreator"
  # Firebase Auth users can create objects (upload epubs)
  # The actual user-level restriction is enforced by Firebase Storage Rules
  member = "allAuthenticatedUsers"
}
