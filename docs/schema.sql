-- =============================================================================
-- alexandria-vector-shelf-mcp: Database Schema
-- Phase 1 — Foundation
-- =============================================================================
-- Run this file in the Supabase SQL editor to initialize the database.
-- Order matters: extensions first, then tables, then indexes, then functions,
-- then RLS policies.
-- =============================================================================


-- =============================================================================
-- 1. Extensions
-- =============================================================================

-- pgvector adds the vector type and similarity search operators to PostgreSQL.
-- This is the core capability that makes semantic search possible.
-- Must be enabled before creating any table with a vector column.
create extension if not exists vector;


-- =============================================================================
-- 2. Tables
-- =============================================================================

-- books
-- Tracks every epub uploaded by a user and its processing state.
-- The client app subscribes to changes on this table via Supabase Realtime
-- to show real-time processing status without polling.
create table if not exists books (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null,             -- identifies the owner
  title         text,                      -- extracted from epub metadata
  author        text,                      -- extracted from epub metadata
  epub_path     text,                      -- path in Supabase Storage bucket
  status        text not null default 'pending',
                                           -- pending | processing | ready | error
  chunk_count   integer not null default 0,
                                           -- total chunks stored after ingestion
  error_message text,                      -- populated only when status = 'error'
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- Add a check constraint to ensure status is always a valid value.
-- This prevents typos from silently corrupting status tracking.
alter table books
  add constraint books_status_check
  check (status in ('pending', 'processing', 'ready', 'error'));


-- chunks
-- Stores every text segment of every book, along with its vector embedding.
-- This is the largest table — a typical 300-page book produces ~600 chunks.
-- All semantic search queries run against this table.
create table if not exists chunks (
  id            uuid primary key default gen_random_uuid(),
  book_id       uuid not null references books(id) on delete cascade,
                                           -- cascade: deleting a book deletes all its chunks
  user_id       uuid not null,             -- denormalized for faster RLS filtering
  content       text not null,             -- the raw text of this chunk
  embedding     vector(1536),              -- output of text-embedding-3-small
                                           -- 1536 is the fixed output dimension of this model
  chunk_index   integer not null,          -- 0-based position in the original book
  chapter       text,                      -- chapter title if extractable from epub
  created_at    timestamptz not null default now()
);


-- =============================================================================
-- 3. Indexes
-- =============================================================================

-- IVFFlat index for approximate nearest neighbor (ANN) search.
--
-- CONCEPT: Why approximate search?
-- Exact nearest neighbor search requires comparing the query vector against every
-- single row in the table — O(n) per query. With 100k chunks this is slow.
-- IVFFlat clusters vectors into `lists` groups during index build, then at query
-- time only searches the most relevant clusters. Much faster, slightly less accurate.
--
-- The `lists` parameter controls the number of clusters:
--   - Rule of thumb: lists = sqrt(total_rows) for datasets under 1M rows
--   - 100 is a good starting value for up to ~500k chunks
--   - Increase to 200-500 when the table grows beyond 500k rows
--
-- `vector_cosine_ops` specifies cosine distance as the similarity metric.
-- We use cosine distance (not Euclidean) because we care about the angle between
-- vectors (semantic direction) not their magnitude (length of the text).
create index if not exists chunks_embedding_idx
  on chunks
  using ivfflat (embedding vector_cosine_ops)
  with (lists = 100);

-- Standard B-tree index on book_id for fast filtering.
-- Every retrieval query filters by book_id first, then does vector search.
-- Without this index, PostgreSQL scans all chunks before filtering — very slow
-- once the table has chunks from many books.
create index if not exists chunks_book_id_idx
  on chunks (book_id);


-- =============================================================================
-- 4. Stored Functions
-- =============================================================================

-- match_chunks: the core retrieval function
-- Called by shared/retriever.py for every user question.
--
-- CONCEPT: Why a stored function?
-- The Supabase Python client doesn't support the <=> cosine distance operator
-- directly. A stored function lets us write the vector search in SQL and call
-- it cleanly from Python via supabase.rpc("match_chunks", {...}).
--
-- Parameters:
--   query_embedding  : the question embedding (same model as chunks)
--   filter_book_id   : restricts search to one book
--   match_count      : number of results to return (top-k)
--
-- Returns: rows with content, book_id, chunk_index, chapter, and similarity score
-- Score is 1 - cosine_distance, so higher = more similar (range: -1 to 1)
create or replace function match_chunks(
  query_embedding vector(1536),
  filter_book_id  uuid,
  match_count     int default 5
)
returns table (
  id          uuid,
  content     text,
  book_id     uuid,
  chunk_index integer,
  chapter     text,
  score       float
)
language sql stable
as $$
  select
    chunks.id,
    chunks.content,
    chunks.book_id,
    chunks.chunk_index,
    chunks.chapter,
    -- cosine similarity: 1 minus the cosine distance
    -- range: -1 (opposite) to 1 (identical), higher is better
    1 - (chunks.embedding <=> query_embedding) as score
  from chunks
  where chunks.book_id = filter_book_id
  order by chunks.embedding <=> query_embedding  -- order by distance ascending
  limit match_count;
$$;


-- =============================================================================
-- 5. Row Level Security (RLS)
-- =============================================================================
-- RLS ensures users can only access their own data, even with the anon key.
-- The service key (used by backend services) bypasses RLS entirely.
-- The anon key (used by the mobile app) is restricted by these policies.

alter table books enable row level security;
alter table chunks enable row level security;

-- Books: users can only see and modify their own books
create policy "users can manage own books"
  on books
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Chunks: users can only see chunks from their own books
create policy "users can read own chunks"
  on chunks
  for select
  using (auth.uid() = user_id);

-- Chunks: only allow insert/update from service role (ingestion pipeline)
-- The anon key cannot write chunks directly — only the backend can.
create policy "service role can manage chunks"
  on chunks
  for all
  using (auth.jwt() ->> 'role' = 'service_role');


-- =============================================================================
-- 6. Realtime
-- =============================================================================
-- Enable Realtime on the books table so the client app receives live status
-- updates during ingestion without polling.
-- Run this in Supabase Dashboard > Database > Replication, or via SQL:

alter publication supabase_realtime add table books;
