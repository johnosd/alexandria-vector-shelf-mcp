# Bibliography — epub-mcp

> Curated learning resources for the epub-mcp project, organized by phase.
> Resources are consumed at the moment each concept appears in the code — not all at once.

---

## Before You Start — Conceptual Foundation

| Type | Resource | Date | Link |
|------|----------|------|------|
| 🎓 Course | **DeepLearning.AI — Building Systems with the ChatGPT API** | 2023 | [deeplearning.ai](https://www.deeplearning.ai/short-courses/building-systems-with-chatgpt/) |
| 🎓 Course | **DeepLearning.AI — LangChain: Chat with Your Data** | 2023 | [deeplearning.ai](https://www.deeplearning.ai/short-courses/langchain-chat-with-your-data/) |
| 📹 Video | **Andrej Karpathy — Deep Dive into LLMs like ChatGPT** | Feb 2025 | [youtube.com](https://www.youtube.com/watch?v=7xTGNNLPyMI) |

### Notes

- The two DeepLearning.AI courses are free and teach **concepts** (chunking, retrieval, RAG pipeline),
  not specific tools. The concepts are still valid even though some code examples use older
  versions of LangChain. Always check current docs when implementing.
- The Karpathy video (3h31m) replaces his 2023 "Intro to LLMs". It covers the full modern
  training stack: pretraining, fine-tuning, RLHF, and reasoning models like DeepSeek-R1.
  Karpathy himself describes the 2023 video as a "parallel video from a long time ago" —
  the 2025 Deep Dive is his current recommended starting point.

---

## Phase 2 — Chunking & Embeddings

| Type | Resource | Date | Link |
|------|----------|------|------|
| 📗 Book | **Hands-On Large Language Models** — Jay Alammar & Maarten Grootendorst (O'Reilly) | Oct 2024 | [oreilly.com](https://www.oreilly.com/library/view/hands-on-large-language/9781098150952/) · [amazon.com](https://www.amazon.com/Hands-Large-Language-Models-Understanding/dp/1098150961) |
| 📄 Article | **Chunking Strategies for LLM Applications** — Pinecone Blog | — | [pinecone.io](https://www.pinecone.io/learn/chunking-strategies/) |
| 📹 Video | **Greg Kamradt — The 5 Levels of Text Splitting for Retrieval** | Jan 2024 | [youtube.com](https://www.youtube.com/watch?v=8OJC21T2SL4) |

### Notes

- The Alammar/Grootendorst book has no real competitor for **visually understanding embeddings**.
  Jay Alammar is the person who made transformers and attention mechanisms understandable to
  millions of engineers through diagrams. The visual-first approach is unique and not replicated
  in any newer book.
- The Pinecone article is a living reference — it gets updated as new strategies emerge.
- Greg Kamradt's video covers all five levels from character splitting to semantic/agent-based
  chunking. Essential before writing a single line of chunking code.

---

## Phase 3 — Retrieval & RAG

| Type | Resource | Date | Link |
|------|----------|------|------|
| 🎓 Course | **DeepLearning.AI — Building and Evaluating Advanced RAG** | 2023 | [deeplearning.ai](https://www.deeplearning.ai/short-courses/building-evaluating-advanced-rag/) |
| 📘 Book | **AI Engineering: Building Applications with Foundation Models** — Chip Huyen (O'Reilly) | 2025 | [oreilly.com](https://www.oreilly.com/library/view/ai-engineering/9781098166298/) · [amazon.com](https://www.amazon.com/AI-Engineering-Building-Applications-Foundation/dp/1098166302) |
| 📄 Paper | **Retrieval-Augmented Generation for Knowledge-Intensive NLP Tasks** — Lewis et al. (original RAG paper) | 2020 | [arxiv.org](https://arxiv.org/abs/2005.11401) |

### Notes

- The DeepLearning.AI Advanced RAG course teaches sentence-window retrieval, auto-merging
  retrieval, and the RAG triad (Context Relevance, Groundedness, Answer Relevance). Concepts
  are still valid; code examples may use older library versions.
- **AI Engineering by Chip Huyen** replaces the previously listed *Building LLMs for Production*
  (Bouchard/Peters, 2024). Huyen's book is more rigorous, published by O'Reilly, and is
  currently the most-read book on the O'Reilly platform. It focuses on timeless engineering
  principles over current trends, and covers RAG, evaluation, agents, fine-tuning, and
  production deployment. Written by a former Stanford ML instructor and NVIDIA engineer.
- The Lewis et al. paper is the original academic foundation for RAG. Short read, worth doing
  once to understand where the terminology comes from.

---

## Phase 5 — MCP (Model Context Protocol)

| Type | Resource | Date | Link |
|------|----------|------|------|
| 📄 Docs | **Model Context Protocol — Introduction** (official) | Current | [modelcontextprotocol.io](https://modelcontextprotocol.io/introduction) |
| 📄 Tutorial | **Building Production MCP Servers** (official) | Current | [modelcontextprotocol.io](https://modelcontextprotocol.io/tutorials/building-mcp-with-llms) |
| 💻 Repo | **MCP Python SDK** | Current | [github.com](https://github.com/modelcontextprotocol/python-sdk) |
| 📹 Video | **Anthropic — MCP Explained** | 2024 | [youtube.com](https://www.youtube.com/watch?v=dHFU5EmUKaw) |
| 💻 Repo | **Awesome MCP Servers** — community reference implementations | Current | [github.com](https://github.com/punkpeye/awesome-mcp-servers) |

### Notes

- Read the official Introduction doc before writing any MCP code (~30 min). It defines the
  core primitives: tools, resources, and prompts — the vocabulary you'll use throughout Phase 5.
- The Python SDK README has enough examples to get started. The Awesome MCP Servers repo is
  useful to see how production projects structure their tools and resources.
- MCP is recent enough that all resources are current by definition. No risk of staleness here.

---

## Changelog

| Date | Change |
|------|--------|
| Apr 2026 | Initial version |
| Apr 2026 | Replaced Karpathy 2023 "Intro to LLMs" with 2025 "Deep Dive into LLMs like ChatGPT" |
| Apr 2026 | Replaced *Building LLMs for Production* (Bouchard, 2024) with *AI Engineering* (Chip Huyen, O'Reilly, 2025) |
| Apr 2026 | Added links to all resources |
| Apr 2026 | Added rationale notes per phase explaining why each resource was chosen or updated |
