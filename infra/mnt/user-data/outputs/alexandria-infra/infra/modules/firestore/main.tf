# =============================================================================
# modules/firestore/main.tf — Firestore Database and Vector Index
# =============================================================================
# CONCEPT: Firestore in Terraform
# Terraform manages the Firestore database configuration and composite indexes.
# Firebase Security Rules are NOT managed here — they are deployed separately
# via Firebase CLI (`firebase deploy --only firestore:rules`) because the
# Terraform Firestore rules resource has limited support.
#
# The most critical resource here is the vector index on the chunks collection.
# Without it, find_nearest() (KNN search) will fail with an error asking you
# to create the index.
# =============================================================================

# ---------------------------------------------------------------------------
# Firestore Database
# ---------------------------------------------------------------------------

resource "google_firestore_database" "main" {
  project     = var.project_id
  name        = "(default)"
  location_id = var.region

  # Native mode is required for:
  #   - Firestore vector search (find_nearest)
  #   - Real-time listeners
  #   - Firebase SDK compatibility
  type = "FIRESTORE_NATIVE"

  # Concurrency mode: OPTIMISTIC uses optimistic locking for transactions.
  # Better performance for read-heavy workloads (which RAG is).
  concurrency_mode = "OPTIMISTIC"

  # Point-in-time recovery: keeps 7 days of history for disaster recovery.
  # Only available in production to control costs.
  point_in_time_recovery_enablement = var.environment == "prod" ? "POINT_IN_TIME_RECOVERY_ENABLED" : "POINT_IN_TIME_RECOVERY_DISABLED"

  # Prevent accidental database deletion
  deletion_policy = var.environment == "prod" ? "PREVENT" : "DELETE"
}

# ---------------------------------------------------------------------------
# Firestore Vector Index — THE critical index for RAG
# ---------------------------------------------------------------------------
# CONCEPT: Why this index is mandatory
# Firestore's find_nearest() (KNN vector search) requires a composite index
# that combines:
#   1. An equality filter field (book_id) — to scope search to one book
#   2. The vector field (embedding) — for KNN similarity computation
#
# Without this index, any call to find_nearest() returns an error with a link
# to create it. We create it here so the app works immediately after deploy.
#
# Index creation takes 5–15 minutes after terraform apply.
# The output will show "CREATING" — wait for "READY" before testing.

resource "google_firestore_index" "chunks_vector" {
  project    = var.project_id
  database   = google_firestore_database.main.name
  collection = "chunks"

  # Query scope: COLLECTION means the index applies to the chunks collection
  query_scope = "COLLECTION"

  fields {
    field_path = "book_id"
    order      = "ASCENDING"
  }

  fields {
    field_path   = "embedding"
    vector_config {
      dimension = 1536  # matches text-embedding-3-small (OpenAI) and
                        # text-embedding-004 with output_dimensionality=1536 (Vertex AI)
      flat {}           # flat = exact KNN (no approximation)
                        # use 'tree_ah' for approximate KNN at scale (>1M docs)
    }
  }

  depends_on = [google_firestore_database.main]
}

# ---------------------------------------------------------------------------
# Additional composite index: list books by user, ordered by date
# ---------------------------------------------------------------------------
# Used by the MCP server's list_books tool and the NeoReader book list screen.

resource "google_firestore_index" "books_by_user" {
  project    = var.project_id
  database   = google_firestore_database.main.name
  collection = "books"

  query_scope = "COLLECTION"

  fields {
    field_path = "user_id"
    order      = "ASCENDING"
  }

  fields {
    field_path = "created_at"
    order      = "DESCENDING"
  }

  depends_on = [google_firestore_database.main]
}

# ---------------------------------------------------------------------------
# NOTE: Firestore Security Rules
# ---------------------------------------------------------------------------
# Security Rules are NOT managed by Terraform due to limited provider support.
# Deploy them separately with Firebase CLI:
#
#   firebase deploy --only firestore:rules
#
# Rules file: firestore.rules (in project root)
# See docs/schema.md for the complete rules definition.
