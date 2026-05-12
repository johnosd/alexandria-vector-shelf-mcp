# =============================================================================
# environments/dev.tfvars — Development environment values
# =============================================================================
# Usage:
#   terraform plan  -var-file="environments/dev.tfvars"
#   terraform apply -var-file="environments/dev.tfvars"
# =============================================================================

project_id  = "your-gcp-project-id"   # ← change this
region      = "us-central1"
environment = "dev"

# Docker images — update after first build + push
# Build: docker build -t us-central1-docker.pkg.dev/<project>/alexandria/ingestion:latest ./ingestion
# Push:  docker push us-central1-docker.pkg.dev/<project>/alexandria/ingestion:latest
ingestion_image = "us-central1-docker.pkg.dev/your-project/alexandria/ingestion:latest"
chat_image      = "us-central1-docker.pkg.dev/your-project/alexandria/chat:latest"

# Chunking parameters
chunk_size    = 500
chunk_overlap = 50

# Retrieval
retrieval_top_k = 5
