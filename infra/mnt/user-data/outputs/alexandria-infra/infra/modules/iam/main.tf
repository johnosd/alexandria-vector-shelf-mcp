# =============================================================================
# modules/iam/main.tf — Service Accounts and IAM Permissions
# =============================================================================
# CONCEPT: Service Accounts in GCP
# A service account is an identity for a machine (not a human).
# Cloud Run services use service accounts to authenticate with other GCP APIs.
#
# Principle of least privilege: each service gets only the permissions
# it actually needs — nothing more.
#
# Ingestion service needs:
#   - Read from Firebase Storage (download epub)
#   - Write to Firestore (store chunks, update status)
#   - Call Vertex AI (generate embeddings)
#   - Access Secret Manager (API keys)
#
# Chat service needs:
#   - Read from Firestore (retrieve chunks)
#   - Call Vertex AI (embed question)
#   - Access Secret Manager (Gemini API key)
# =============================================================================

# ---------------------------------------------------------------------------
# Ingestion Service Account
# ---------------------------------------------------------------------------

resource "google_service_account" "ingestion" {
  account_id   = "alexandria-ingestion"
  display_name = "Alexandria Ingestion Service"
  description  = "Used by the Cloud Run ingestion service to process epub files"
  project      = var.project_id
}

# Read objects from Firebase Storage (download epub)
resource "google_project_iam_member" "ingestion_storage_reader" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.ingestion.email}"
}

# Write to Firestore (store chunks + update book status)
resource "google_project_iam_member" "ingestion_firestore_writer" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.ingestion.email}"
}

# Call Vertex AI Prediction API (generate embeddings)
resource "google_project_iam_member" "ingestion_vertex_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.ingestion.email}"
}

# Read secrets from Secret Manager (OpenAI API key)
resource "google_project_iam_member" "ingestion_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.ingestion.email}"
}

# ---------------------------------------------------------------------------
# Chat Service Account
# ---------------------------------------------------------------------------

resource "google_service_account" "chat" {
  account_id   = "alexandria-chat"
  display_name = "Alexandria Chat Service"
  description  = "Used by the Cloud Run chat service to answer user questions"
  project      = var.project_id
}

# Read from Firestore (retrieve chunks for RAG)
resource "google_project_iam_member" "chat_firestore_reader" {
  project = var.project_id
  role    = "roles/datastore.viewer"
  member  = "serviceAccount:${google_service_account.chat.email}"
}

# Call Vertex AI (embed user question)
resource "google_project_iam_member" "chat_vertex_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.chat.email}"
}

# Read secrets (Gemini API key)
resource "google_project_iam_member" "chat_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.chat.email}"
}
