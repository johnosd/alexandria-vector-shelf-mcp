# Phase 1 — Foundation Setup Guide

This guide walks through every setup step for Phase 1 in order.
Complete each section before moving to the next.
At the end you will have a fully configured Firebase project, Firestore ready for
vector search, and the repository skeleton committed to GitHub.

---

## Prerequisites

Install these tools before starting:

```bash
# Google Cloud CLI
brew install google-cloud-sdk        # macOS
# or follow: https://cloud.google.com/sdk/docs/install

# Firebase CLI
npm install -g firebase-tools

# Python 3.11
brew install python@3.11

# Docker
# Download from https://www.docker.com/products/docker-desktop
```

---

## Step 1: Create the GitHub repository

```bash
# Create repository on GitHub: public, name "alexandria-vector-shelf-mcp", no template
# Then clone locally:
git clone https://github.com/<your-username>/alexandria-vector-shelf-mcp.git
cd alexandria-vector-shelf-mcp
```

Copy all project files into the cloned repository, then:

```bash
git add .
git commit -m "feat: Phase 1 foundation — project structure, Firestore schema, shared modules"
git push origin main
```

---

## Step 2: Create the Google Cloud / Firebase project

1. Go to [https://console.firebase.google.com](https://console.firebase.google.com)
2. Click **Add project**
3. Name: `alexandria-vector-shelf-mcp`
4. Disable Google Analytics (not needed for this project)
5. Click **Create project** — wait ~1 minute

Note your **Project ID** (shown in project settings) — you will need it in every
gcloud and Firebase CLI command.

---

## Step 3: Enable Firestore

1. In Firebase console → **Build** → **Firestore Database**
2. Click **Create database**
3. Select **Native mode** (not Datastore mode — vector search requires Native mode)
4. Select region: `us-central1` (or your closest region)
5. Click **Done**

---

## Step 4: Enable Firebase Auth

1. In Firebase console → **Build** → **Authentication**
2. Click **Get started**
3. Enable **Anonymous** sign-in (Settings → Sign-in method → Anonymous → Enable)
4. Optionally enable **Google** sign-in for later phases

Anonymous auth gives every user a `uid` without requiring a login screen.
This provides the `user_id` needed to isolate each user's chunks in Firestore.

---

## Step 5: Create Firebase Storage bucket

1. In Firebase console → **Build** → **Storage**
2. Click **Get started**
3. Select **Start in production mode** (we will write security rules manually)
4. Select same region as Firestore: `us-central1`

Storage is used to hold the original `.epub` files. The ingestion service downloads
them from Storage via a signed URL.

---

## Step 6: Deploy Firestore Security Rules

Create `firestore.rules` in the project root:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    match /users/{userId} {
      allow read, write: if request.auth != null
                         && request.auth.uid == userId;
    }

    match /books/{bookId} {
      allow read, write: if request.auth != null
                         && request.auth.uid == resource.data.user_id;
      allow create: if request.auth != null
                    && request.auth.uid == request.resource.data.user_id;
    }

    match /chunks/{chunkId} {
      allow read: if request.auth != null
                  && request.auth.uid == resource.data.user_id;
      allow write: if false;  // server-side only via Admin SDK
    }
  }
}
```

Deploy:
```bash
firebase login
firebase use <your-project-id>
firebase deploy --only firestore:rules
```

---

## Step 7: Create the Firestore vector index

This is the most important setup step. Without this index, the retriever will fail.

```bash
# Authenticate with gcloud
gcloud auth login
gcloud config set project <your-project-id>

# Create the composite vector index
gcloud firestore indexes composite create \
  --collection-group=chunks \
  --query-scope=COLLECTION \
  --field-config=order=ASCENDING,field-path="book_id" \
  --field-config=field-path="embedding",vector-config='{"dimension":"1536","flat":"{}"}' \
  --database="(default)"
```

Index creation takes 5–15 minutes. Check status:
```bash
gcloud firestore indexes composite list
```

Wait until status shows `READY` before proceeding to Phase 2.

**Note on dimension:** `1536` matches `text-embedding-3-small` (OpenAI) and can also be
used with Vertex AI `text-embedding-004` (which supports configurable output dimensions).
If you later switch to a different model with a different dimension, you must delete this
index and create a new one.

---

## Step 8: Download service account credentials

For local development, the services authenticate with a service account JSON file.

1. Firebase console → **Project settings** (gear icon) → **Service accounts**
2. Click **Generate new private key**
3. Save as `service-account.json` in the project root
4. **Add `service-account.json` to `.gitignore` immediately** — it must never be committed

```bash
echo "service-account.json" >> .gitignore
git add .gitignore
git commit -m "chore: ensure service account key is gitignored"
```

In production (Cloud Run), services use the attached service account automatically
via Application Default Credentials — the JSON file is only needed locally.

---

## Step 9: Configure environment variables

```bash
cp .env.example .env
```

Fill in `.env`:

```bash
GOOGLE_CLOUD_PROJECT=<your-project-id>
FIREBASE_STORAGE_BUCKET=<your-project-id>.appspot.com
GOOGLE_APPLICATION_CREDENTIALS=./service-account.json

# Choose embedding provider (start with OpenAI — simpler setup)
OPENAI_API_KEY=<your-openai-key>
EMBEDDING_MODEL=text-embedding-3-small

# LLM
GEMINI_API_KEY=<your-gemini-key>   # get at https://aistudio.google.com/apikey

ENVIRONMENT=development
CHUNK_SIZE=500
CHUNK_OVERLAP=50
RETRIEVAL_TOP_K=5
```

---

## Step 10: Verify the setup

Run this script from the project root to verify Firestore connectivity:

```python
# verify_setup.py
import os
from dotenv import load_dotenv

load_dotenv()
os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = "./service-account.json"

import firebase_admin
from firebase_admin import credentials, firestore

cred = credentials.Certificate("./service-account.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

# Write a test document
db.collection("_setup_test").document("ping").set({"status": "ok"})
doc = db.collection("_setup_test").document("ping").get()
print(f"Firestore connected: {doc.to_dict()}")

# Clean up
db.collection("_setup_test").document("ping").delete()
print("Setup verified successfully. Ready for Phase 2.")
```

```bash
python verify_setup.py
```

**Expected output:**
```
Firestore connected: {'status': 'ok'}
Setup verified successfully. Ready for Phase 2.
```

---

## Phase 1 complete ✅

Checklist before moving to Phase 2:

- [ ] GitHub repository created and pushed
- [ ] Firebase project created (`alexandria-vector-shelf-mcp`)
- [ ] Firestore in Native mode, region `us-central1`
- [ ] Firebase Auth enabled (Anonymous)
- [ ] Firebase Storage bucket created
- [ ] Firestore Security Rules deployed
- [ ] Vector index created (status: READY)
- [ ] Service account JSON downloaded and gitignored
- [ ] `.env` filled with real credentials
- [ ] `verify_setup.py` runs successfully

**Next:** Phase 2 — Ingestion Service
(`ingestion/parser.py` → `ingestion/chunker.py` → `ingestion/embedder.py` → `ingestion/store.py`)
