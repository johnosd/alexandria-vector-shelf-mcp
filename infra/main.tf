# =============================================================================
# alexandria-vector-shelf-mcp — Terraform Root Module
# =============================================================================
# CONCEPT: What is Terraform?
# Terraform is an Infrastructure as Code (IaC) tool. Instead of clicking
# through the GCP console to create services, you declare what you want
# in .tf files and Terraform figures out how to create, update, or destroy
# resources to match your declaration.
#
# Think of it like a data pipeline DAG: Terraform resolves dependencies
# between resources automatically — if Cloud Run needs a service account,
# Terraform creates the service account first, then Cloud Run.
#
# CONCEPT: Providers
# A provider is the plugin that knows how to talk to a specific cloud API.
# The "google" provider knows how to create GCP resources.
# The "google-beta" provider has access to newer/beta GCP features.
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }

  # CONCEPT: Remote state
  # Terraform tracks what it has created in a "state file".
  # Storing it in GCS (instead of locally) means:
  #   - state is never lost if your laptop dies
  #   - multiple team members share the same state
  #   - CI/CD pipelines can run Terraform safely
  #
  # Create the bucket manually ONCE before running terraform init:
  #   gcloud storage buckets create gs://<your-project-id>-tfstate \
  #     --location=us-central1 \
  #     --uniform-bucket-level-access
  backend "gcs" {
    bucket = "alexandria-vector-shelf-mcp-tfstate" # change to your project id
    prefix = "terraform/state"
  }
}

# =============================================================================
# Provider configuration
# =============================================================================

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# =============================================================================
# Enable required GCP APIs
# =============================================================================
# CONCEPT: GCP APIs must be explicitly enabled before resources can be created.
# This is equivalent to going to GCP Console → APIs & Services → Enable.
# Terraform manages this as a resource so it's reproducible.

locals {
  required_apis = [
    "run.googleapis.com",           # Cloud Run
    "firestore.googleapis.com",     # Firestore
    "storage.googleapis.com",       # Cloud Storage / Firebase Storage
    "aiplatform.googleapis.com",    # Vertex AI
    "iam.googleapis.com",           # IAM
    "secretmanager.googleapis.com", # Secret Manager (for API keys)
    "firebase.googleapis.com",      # Firebase
    "identitytoolkit.googleapis.com", # Firebase Auth
  ]
}

resource "google_project_service" "apis" {
  for_each = toset(local.required_apis)

  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = false

  # Do not disable the API when destroying this resource
  # Some APIs take time to disable and can break other resources
  disable_on_destroy = false
}

# =============================================================================
# Modules
# =============================================================================

module "iam" {
  source     = "./modules/iam"
  project_id = var.project_id

  depends_on = [google_project_service.apis]
}

module "storage" {
  source      = "./modules/storage"
  project_id  = var.project_id
  region      = var.region
  environment = var.environment

  depends_on = [google_project_service.apis]
}

module "firestore" {
  source     = "./modules/firestore"
  project_id = var.project_id
  region     = var.region

  depends_on = [google_project_service.apis]
}

module "cloud_run" {
  source     = "./modules/cloud_run"
  project_id = var.project_id
  region     = var.region
  environment = var.environment

  # Service account created by IAM module
  ingestion_service_account = module.iam.ingestion_service_account_email
  chat_service_account      = module.iam.chat_service_account_email

  # Storage bucket name for ingestion service env var
  storage_bucket = module.storage.epub_bucket_name

  depends_on = [
    module.iam,
    module.storage,
    module.firestore,
  ]
}
