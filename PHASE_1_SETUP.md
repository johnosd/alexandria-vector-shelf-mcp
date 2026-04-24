# Phase 1 — Foundation Setup Guide

This guide walks through every step of Phase 1 in order.
Complete each section before moving to the next.

---

## Step 1: Create the GitHub repository

```bash
# Create the repository on GitHub (public, no template)
# Then clone it locally:
git clone https://github.com/<your-username>/alexandria-vector-shelf-mcp.git
cd alexandria-vector-shelf-mcp
```

Copy all files from this deliverable into the cloned repository.

```bash
git add .
git commit -m "feat: Phase 1 foundation — schema, shared modules, project structure"
git push origin main
```

---

## Step 2: Create the Supabase project

1. Go to [https://app.supabase.com](https://app.supabase.com) and sign in
2. Click **New project**
3. Name: `alexandria-vector-shelf-mcp`
4. Database password: generate a strong one and save it
5. Region: choose the closest to you (South America — São Paulo if available)
6. Wait ~2 minutes for the project to provision

---

## Step 3: Configure Supabase Storage

1. In your Supabase project, go to **Storage**
2. Click **New bucket**
3. Name: `epubs`
4. Toggle: **Private** (not public — epubs should only be accessible via signed URLs)
5. Click **Save**

---

## Step 4: Run the database schema

1. In your Supabase project, go to **SQL Editor**
2. Click **New query**
3. Copy the entire contents of `docs/schema.sql`
4. Click **Run**
5. Verify in **Table Editor** that you can see the `books` and `chunks` tables

**Expected output:** No errors. Two tables visible in Table Editor.

---

## Step 5: Configure environment variables

```bash
cp .env.example .env
```

Open `.env` and fill in:

| Variable | Where to find it |
|---|---|
| `SUPABASE_URL` | Supabase → Settings → API → Project URL |
| `SUPABASE_SERVICE_KEY` | Supabase → Settings → API → service_role key |
| `SUPABASE_ANON_KEY` | Supabase → Settings → API → anon public key |
| `OPENAI_API_KEY` | https://platform.openai.com/api-keys |

Leave all other variables at their defaults for now.

---

## Step 6: Verify the database connection

Create a quick test script to verify everything is connected:

```python
# test_connection.py — run this from the project root
# python test_connection.py

import os
from dotenv import load_dotenv

load_dotenv()

from shared.db import supabase

# Try to list tables (should return empty list, not an error)
response = supabase.table("books").select("id").limit(1).execute()
print("Connection successful!")
print(f"Books table accessible: {response.data is not None}")

response = supabase.table("chunks").select("id").limit(1).execute()
print(f"Chunks table accessible: {response.data is not None}")
```

**Expected output:**
```
Connection successful!
Books table accessible: True
Chunks table accessible: True
```

---

## Step 7: Enable Supabase Realtime

1. In your Supabase project, go to **Database → Replication**
2. Find the `books` table
3. Toggle **Insert**, **Update**, **Delete** to ON
4. This enables the client app to receive live status updates

Alternatively, the `schema.sql` already contains:
```sql
alter publication supabase_realtime add table books;
```
This runs automatically when you execute the schema.

---

## Step 8: Verify the schema

Run this query in the SQL Editor to verify all objects were created correctly:

```sql
-- Check tables exist
select table_name
from information_schema.tables
where table_schema = 'public'
order by table_name;
-- Expected: books, chunks

-- Check pgvector extension is enabled
select extname from pg_extension where extname = 'vector';
-- Expected: one row with "vector"

-- Check the match_chunks function exists
select routine_name
from information_schema.routines
where routine_schema = 'public' and routine_name = 'match_chunks';
-- Expected: one row with "match_chunks"

-- Check indexes exist
select indexname from pg_indexes
where tablename in ('books', 'chunks')
order by indexname;
-- Expected: chunks_book_id_idx, chunks_embedding_idx, plus primary key indexes
```

---

## Phase 1 complete ✅

At the end of Phase 1 you should have:

- [ ] GitHub repository created and pushed
- [ ] Supabase project provisioned
- [ ] `epubs` storage bucket created (private)
- [ ] Schema deployed (`books`, `chunks`, `match_chunks` function, RLS policies)
- [ ] `.env` filled with real credentials
- [ ] Database connection verified with test script
- [ ] Realtime enabled on `books` table

**Next:** Phase 2 — Ingestion Service (`ingestion/parser.py`, `ingestion/chunker.py`, `ingestion/embedder.py`, `ingestion/store.py`)
