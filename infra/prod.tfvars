# environments/prod.tfvars — Production environment values

project_id  = "your-gcp-project-id-prod"  # ← use a separate GCP project for prod
region      = "us-central1"
environment = "prod"

ingestion_image = "us-central1-docker.pkg.dev/your-project-prod/alexandria/ingestion:v1.0.0"
chat_image      = "us-central1-docker.pkg.dev/your-project-prod/alexandria/chat:v1.0.0"

chunk_size      = 500
chunk_overlap   = 50
retrieval_top_k = 5
