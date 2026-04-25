# =============================================================================
# alexandria-vector-shelf-mcp — Makefile
# =============================================================================

.PHONY: setup dev dev-ingestion dev-chat test test-unit test-integration lint format ingest chat clean help

help:
	@echo ""
	@echo "alexandria-vector-shelf-mcp — available commands"
	@echo ""
	@echo "  make setup            Install dependencies and copy .env"
	@echo "  make dev              Start all services (docker-compose)"
	@echo "  make dev-ingestion    Start ingestion service only"
	@echo "  make dev-chat         Start chat service only"
	@echo "  make test             Run all tests"
	@echo "  make test-unit        Run unit tests only (no Firebase)"
	@echo "  make test-integration Run integration tests (requires Firebase)"
	@echo "  make lint             Lint all Python files with ruff"
	@echo "  make format           Format all Python files with ruff"
	@echo "  make ingest           Test ingestion via curl (see usage below)"
	@echo "  make index            Create Firestore vector index via gcloud"
	@echo "  make clean            Remove __pycache__ and temp files"
	@echo ""
	@echo "Usage examples:"
	@echo "  make ingest EPUB_URL=https://... BOOK_ID=abc123 USER_ID=uid456"
	@echo "  make chat BOOK_ID=abc123 USER_ID=uid456 QUESTION='What is this about?'"
	@echo ""

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

setup:
	@echo "Setting up local environment..."
	cp -n .env.example .env || echo ".env already exists, skipping"
	pip install -r ingestion/requirements.txt
	pip install -r chat/requirements.txt
	@echo ""
	@echo "Done. Next steps:"
	@echo "  1. Fill in .env with your Firebase and API credentials"
	@echo "  2. Download service-account.json from Firebase console"
	@echo "  3. Run: make index  (creates Firestore vector index)"
	@echo "  4. Run: python verify_setup.py"

# ---------------------------------------------------------------------------
# Development
# ---------------------------------------------------------------------------

dev:
	docker-compose up --build

dev-ingestion:
	docker-compose up --build ingestion

dev-chat:
	docker-compose up --build chat

# ---------------------------------------------------------------------------
# Firestore index creation (run once before Phase 2)
# ---------------------------------------------------------------------------

index:
	@test -n "$(GOOGLE_CLOUD_PROJECT)" || (echo "Error: GOOGLE_CLOUD_PROJECT is not set in your environment" && exit 1)
	gcloud firestore indexes composite create \
		--collection-group=chunks \
		--query-scope=COLLECTION \
		--field-config=order=ASCENDING,field-path="book_id" \
		--field-config=field-path="embedding",vector-config='{"dimension":"1536","flat":"{}"}' \
		--database="(default)" \
		--project=$(GOOGLE_CLOUD_PROJECT)
	@echo "Index creation started. Check status with: gcloud firestore indexes composite list"

# ---------------------------------------------------------------------------
# Testing
# ---------------------------------------------------------------------------

test:
	pytest tests/ -v --tb=short

test-unit:
	pytest tests/ -v --tb=short -m "unit"

test-integration:
	pytest tests/ -v --tb=short -m "integration"

# ---------------------------------------------------------------------------
# Code quality
# ---------------------------------------------------------------------------

lint:
	ruff check ingestion/ chat/ shared/ mcp/ tests/

format:
	ruff format ingestion/ chat/ shared/ mcp/ tests/

# ---------------------------------------------------------------------------
# Manual pipeline testing via curl
# ---------------------------------------------------------------------------

ingest:
	@test -n "$(EPUB_URL)"  || (echo "Error: EPUB_URL required.  Usage: make ingest EPUB_URL=... BOOK_ID=... USER_ID=..." && exit 1)
	@test -n "$(BOOK_ID)"   || (echo "Error: BOOK_ID required." && exit 1)
	@test -n "$(USER_ID)"   || (echo "Error: USER_ID required." && exit 1)
	curl -s -X POST http://localhost:8001/ingest \
		-H "Content-Type: application/json" \
		-d '{"epub_url":"$(EPUB_URL)","book_id":"$(BOOK_ID)","user_id":"$(USER_ID)"}' \
		| python3 -m json.tool

chat:
	@test -n "$(BOOK_ID)"   || (echo "Error: BOOK_ID required.  Usage: make chat BOOK_ID=... USER_ID=... QUESTION=..." && exit 1)
	@test -n "$(USER_ID)"   || (echo "Error: USER_ID required." && exit 1)
	@test -n "$(QUESTION)"  || (echo "Error: QUESTION required." && exit 1)
	curl -N "http://localhost:8002/chat?book_id=$(BOOK_ID)&user_id=$(USER_ID)&question=$(QUESTION)"

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

clean:
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -name "*.pyc" -delete 2>/dev/null || true
	find . -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
	find . -name ".ruff_cache" -exec rm -rf {} + 2>/dev/null || true
