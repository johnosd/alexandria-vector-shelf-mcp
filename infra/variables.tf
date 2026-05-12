# =============================================================================
# variables.tf — Input variables for the root module
# =============================================================================
# CONCEPT: Variables in Terraform
# Variables are like function parameters — they let you reuse the same
# infrastructure definition across environments (dev, prod) by changing
# only the values, not the code.
#
# Values are provided via:
#   - .tfvars files (environments/dev.tfvars, environments/prod.tfvars)
#   - Environment variables (TF_VAR_project_id)
#   - CLI flags (-var="project_id=my-project")
# =============================================================================

variable "project_id" {
  description = "GCP project ID (find in Firebase console → Project Settings)"
  type        = string
  # No default — must be explicitly provided. Prevents accidental deploys
  # to the wrong project.
}

variable "region" {
  description = "GCP region for all resources"
  type        = string
  default     = "us-central1"
  # us-central1 has the widest service availability for GCP.
  # For lower latency from Brazil, southamerica-east1 (São Paulo) is available
  # for Cloud Run and Storage but may not support all Vertex AI models yet.
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod"
  }
}

variable "ingestion_image" {
  description = "Docker image URI for the ingestion service (Artifact Registry)"
  type        = string
  # Example: us-central1-docker.pkg.dev/my-project/alexandria/ingestion:latest
  # Set in tfvars after first docker build + push
}

variable "chat_image" {
  description = "Docker image URI for the chat service (Artifact Registry)"
  type        = string
  # Example: us-central1-docker.pkg.dev/my-project/alexandria/chat:latest
}

variable "openai_api_key_secret" {
  description = "Secret Manager secret name for OpenAI API key"
  type        = string
  default     = "openai-api-key"
  # Create the secret manually once:
  # gcloud secrets create openai-api-key --data-file=- <<< "sk-..."
}

variable "gemini_api_key_secret" {
  description = "Secret Manager secret name for Gemini API key"
  type        = string
  default     = "gemini-api-key"
}

variable "chunk_size" {
  description = "Maximum characters per chunk (ingestion pipeline)"
  type        = number
  default     = 500
}

variable "chunk_overlap" {
  description = "Overlap characters between consecutive chunks"
  type        = number
  default     = 50
}

variable "retrieval_top_k" {
  description = "Number of chunks to retrieve per question"
  type        = number
  default     = 5
}
