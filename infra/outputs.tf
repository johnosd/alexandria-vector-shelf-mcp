# =============================================================================
# outputs.tf — Values exported after terraform apply
# =============================================================================
# CONCEPT: Outputs
# Outputs are the "return values" of your Terraform configuration.
# After `terraform apply`, these values are printed to the terminal.
# They are also accessible to other Terraform configurations via
# `terraform output` or as remote state data sources.
#
# Use these URLs to configure your .env file and NeoReader app.
# =============================================================================

output "ingestion_service_url" {
  description = "URL of the deployed ingestion Cloud Run service"
  value       = module.cloud_run.ingestion_service_url
}

output "chat_service_url" {
  description = "URL of the deployed chat Cloud Run service"
  value       = module.cloud_run.chat_service_url
}

output "epub_bucket_name" {
  description = "Firebase Storage bucket name for epub uploads"
  value       = module.storage.epub_bucket_name
}

output "firestore_database_id" {
  description = "Firestore database ID"
  value       = module.firestore.database_id
}

output "ingestion_service_account" {
  description = "Service account email used by the ingestion Cloud Run service"
  value       = module.iam.ingestion_service_account_email
}

output "chat_service_account" {
  description = "Service account email used by the chat Cloud Run service"
  value       = module.iam.chat_service_account_email
}

output "next_steps" {
  description = "Post-deployment configuration steps"
  value       = <<-EOT
    ✅ Infrastructure deployed successfully.

    Next steps:
    1. Copy these values to your .env file:
       INGESTION_SERVICE_URL = ${module.cloud_run.ingestion_service_url}
       CHAT_SERVICE_URL      = ${module.cloud_run.chat_service_url}
       FIREBASE_STORAGE_BUCKET = ${module.storage.epub_bucket_name}

    2. Create Firestore vector index (one-time, takes ~10 min):
       gcloud firestore indexes composite create \
         --collection-group=chunks \
         --field-config=order=ASCENDING,field-path="book_id" \
         --field-config=field-path="embedding",vector-config='{"dimension":"1536","flat":"{}"}'

    3. Deploy Firebase Security Rules (not managed by Terraform):
       firebase deploy --only firestore:rules,storage

    4. Enable Firebase Auth in Firebase console (not managed by Terraform):
       https://console.firebase.google.com → Authentication → Get started
  EOT
}
