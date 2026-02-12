# 2.21. Session History Indexing

## Overview

Use the existing FAISS/vector infrastructure (`libocvector`) to create vector indexes of chat session history. Enables semantic search over past conversations (e.g. "find when we discussed X") and potential use of history context in tools or prompts.

## Status

📋 **PLANNED** - To be implemented.

## Goals

1. Index session history (messages, summaries, or both) into vector indexes using the same FAISS/embedding pipeline as codebase search
2. Store metadata (session id, message id, role, timestamp) so results can be resolved back to sessions and messages
3. Support search over history (e.g. from a tool or UI) without pulling full session JSON every time
4. Reuse `libocvector` (Database, Index, embedding API) and existing patterns from Codebase Search / Documentation indexing

## Current Architecture (Reuse)

- **libocvector**: `Database`, `Index`, FAISS C wrapper, embedding generation, `add_documents()` / `search()`
- **libollmchat/History**: `Session`, `SessionBase`, `Manager`, `SessionJson` — sessions with `messages`, persistence to SQLite + JSON
- **Codebase Search (2.10)**: Vector indexing of code (and optionally docs); SQL metadata + FAISS index; background scan and incremental updates

## Proposed Approach

### What to index

- **Option A**: Individual messages (user + assistant) as separate vectors; metadata: session_id, message_id, role, timestamp
- **Option B**: Session-level summaries (e.g. per-session or per-turn summary) to keep index smaller; metadata: session_id, timestamp
- **Option C**: Both — summaries for coarse search, message-level for fine-grained retrieval

Text to embed: message content (and optionally role prefix, e.g. "user: ..." / "assistant: ...") or generated summary text.

### Storage

- **FAISS index**: One or more history index files (e.g. per-user or global), same pattern as project codebase index
- **SQL metadata**: Table(s) mapping vector_id → session_id, message_id (or chunk_id), role, timestamp, optional snippet — similar to codebase search file/line metadata

### Integration points

- **When to index**: On session save (incremental); or background job that walks history and (re)indexes new or updated sessions
- **When to update**: Session saved → add/update vectors for that session’s (new or changed) messages; optionally mark session as dirty and batch later
- **Search**: New tool (e.g. `search_history`) or internal API that runs `Database.search()` on the history index and returns session/message references (and optionally snippets)

## Implementation Tasks

- [ ] **Metadata schema**: Define SQL table(s) for history vector metadata (session_id, message_id, role, timestamp, optional text snippet)
- [ ] **History index lifecycle**: Create/open FAISS index for history (path config, dimension from embedding model); reuse `Database` / `Index` pattern from libocvector
- [ ] **Indexing pipeline**: From `Session` / `SessionJson` (or Manager), extract message text → optional summarization → embed → add to index; record metadata
- [ ] **Incremental updates**: On session save (or via a dedicated "index history" path), add or update only affected sessions/messages; avoid full reindex when possible
- [ ] **Search API**: Query history index by text; return list of (session_id, message_id, snippet/distance) for UI or tool use
- [ ] **Tool (optional)**: Expose `search_history` (or similar) so the LLM can search past conversations
- [ ] **Configuration**: Index path, embedding model, whether to index on save vs. on-demand, limits (e.g. last N sessions or last N days)

## Files to Create/Modify

- **New**: History indexer component (e.g. under `libocvector/Indexing/` or `libollmchat/History/`) that uses `OLLMvector.Database` and metadata store
- **New (optional)**: `liboctools/SearchHistory/` or similar for a search-history tool
- **Modify**: History save path (e.g. `Session.save` or Manager) to trigger incremental indexing, or add explicit "index history" entry point
- **Reuse**: `libocvector/Database.vala`, `Index.vala`, FAISS wrapper, embedding API; `libollmchat/History/Session.vala`, `SessionJson.vala`, `Manager.vala`

## Related Plans

- **2.10** - Codebase Search Tool (vector indexing, FAISS, metadata schema pattern)
- **2.13** - Documentation Indexing Tool (similar indexing workflow and repository/shared DB ideas)
- **2.10.3** - File-based vector entries / what gets vectorized

## Notes

- Keep history index separate from project codebase index (different index files and metadata tables) to avoid mixing and to allow different retention/update policies
- Consider privacy and size: indexing full message content may be large; summaries or recent-window-only can reduce size and exposure
