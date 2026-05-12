# infra/ — Terraform Infrastructure

Manages all GCP infrastructure for `alexandria-vector-shelf-mcp` as code.

## What Terraform manages

| Resource | Terraform | Manual |
|---|---|---|
| Cloud Run — Ingestion Service | ✅ | — |
| Cloud Run — Chat Service | ✅ | — |
| Firestore Database | ✅ | — |
| Firestore Vector Index (chunks) | ✅ | — |
| Firebase Storage Bucket | ✅ | — |
| IAM Service Accounts | ✅ | — |
| GCP API enablement | ✅ | — |
| Firebase Auth | — | ✅ Firebase console |
| Firestore Security Rules | — | ✅ `firebase deploy` |
| Firebase Storage Rules | — | ✅ `firebase deploy` |

## Prerequisites

```bash
# Install Terraform
brew install terraform

# Install Google Cloud CLI
brew install google-cloud-sdk

# Authenticate
gcloud auth login
gcloud auth application-default login

# Create state bucket (once only)
gcloud storage buckets create gs://<your-project-id>-tfstate \
  --location=us-central1 \
  --uniform-bucket-level-access

# Create API key secrets (once only)
gcloud secrets create openai-api-key --data-file=- <<< "sk-your-key"
gcloud secrets create gemini-api-key --data-file=- <<< "your-gemini-key"
```

## First deploy

```bash
cd infra/

# 1. Initialize Terraform (downloads providers, connects to state bucket)
terraform init

# 2. Preview what will be created
terraform plan -var-file="environments/dev.tfvars"

# 3. Apply (creates all resources)
terraform apply -var-file="environments/dev.tfvars"

# 4. Deploy Firebase rules (not managed by Terraform)
firebase deploy --only firestore:rules,storage
```

## Useful commands

```bash
# See current state
terraform show

# See specific output value
terraform output ingestion_service_url

# Destroy everything (careful in prod!)
terraform destroy -var-file="environments/dev.tfvars"

# Format all .tf files
terraform fmt -recursive

# Validate configuration
terraform validate
```

## Module structure

```
infra/
├── main.tf           ← root module, calls all child modules
├── variables.tf      ← input variables
├── outputs.tf        ← exported values (URLs, bucket names)
├── environments/
│   ├── dev.tfvars    ← dev environment values
│   └── prod.tfvars   ← prod environment values
└── modules/
    ├── iam/          ← service accounts + IAM roles
    ├── storage/      ← Firebase Storage bucket
    ├── firestore/    ← Firestore database + vector index
    └── cloud_run/    ← ingestion + chat Cloud Run services
```

## Adding the infra/ folder to the main repository

Place the `infra/` folder at the root of `alexandria-vector-shelf-mcp/`:

```
alexandria-vector-shelf-mcp/
├── infra/            ← here
├── ingestion/
├── chat/
├── shared/
├── docs/
└── ...
```
