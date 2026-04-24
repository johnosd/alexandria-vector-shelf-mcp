# =============================================================================
# alexandria-vector-shelf-mcp — Makefile
# =============================================================================
# Standardized commands for development, testing, and deployment.
# All commands assume you have Docker and Python 3.11+ installed.
#
# Usage:
#   make setup        prepare local environment
#   make dev          start all services locally
#   make test         run all tests
#   make ingest       test ingestion pipeline with a local epub
# =============================================================================

.PHONY: setup dev test lint ingest chat clean help

# Default target
help:
	@echo ""
	@echo "alexandria-vector-shelf-mcp — available commands"
	@echo ""
	@echo "  make setup       Install dependencies and prepare environment"
	@echo "  make dev         Start all services with docker-compose"
	@echo "  make test        Run all tests"
	@echo "  make lint        Run ruff linter across all services"
	@echo "  make ingest      Test ingestion (requires EPUB, BOOK_ID, USER_ID)"
	@echo "  make clean       Remove __pycache__ and .pyc files"
	@echo ""

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

setup:
	@echo "Setting up local environment..."
	cp -n .env.example .env || true
	pip install -r ingestion/requirements.txt
	pip install -r chat/requirements.txt
	@echo "Done. Fill in .env with your Supabase and OpenAI credentials."

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
# Testing
# ---------------------------------------------------------------------------

test:
	pytest tests/ -v --tb=short

test-unit:
	pytest tests/ -v --tb=short -m "not integration"

test-integration:
	pytest tests/ -v --tb=short -m integration

# ---------------------------------------------------------------------------
# Code quality
# ---------------------------------------------------------------------------

lint:
	ruff check ingestion/ chat/ shared/ mcp/

format:
	ruff format ingestion/ chat/ shared/ mcp/

# ---------------------------------------------------------------------------
# Manual pipeline testing
# ---------------------------------------------------------------------------
# Test the ingestion pipeline end-to-end via curl.
# Requires a running ingestion service (make dev-ingestion).
#
# Usage:
#   make ingest EPUB_URL=https://... BOOK_ID=<uuid> USER_ID=<uuid>
# ---------------------------------------------------------------------------

ingest:
	@test -n "$(EPUB_URL)" || (echo "Error: EPUB_URL is required. Usage: make ingest EPUB_URL=https://... BOOK_ID=<uuid> USER_ID=<uuid>" && exit 1)
	@test -n "$(BOOK_ID)" || (echo "Error: BOOK_ID is required." && exit 1)
	@test -n "$(USER_ID)" || (echo "Error: USER_ID is required." && exit 1)
	curl -s -X POST http://localhost:8001/ingest \
		-H "Content-Type: application/json" \
		-d '{"epub_url": "$(EPUB_URL)", "book_id": "$(BOOK_ID)", "user_id": "$(USER_ID)"}' \
		| python3 -m json.tool

# Test the chat service with a sample question.
# Usage: make chat BOOK_ID=<uuid> USER_ID=<uuid> QUESTION="What is this book about?"
chat:
	@test -n "$(BOOK_ID)" || (echo "Error: BOOK_ID is required." && exit 1)
	@test -n "$(USER_ID)" || (echo "Error: USER_ID is required." && exit 1)
	@test -n "$(QUESTION)" || (echo "Error: QUESTION is required." && exit 1)
	curl -N "http://localhost:8002/chat?book_id=$(BOOK_ID)&user_id=$(USER_ID)&question=$(QUESTION)"

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

clean:
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -name "*.pyc" -delete 2>/dev/null || true
	find . -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
