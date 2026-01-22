# 2.13. Documentation Indexing Tool

## Overview

Documentation indexing system for making documentation searchable and accessible to the LLM. Uses similar logic to the Codebase Search Tool with the VectorSearch infrastructure.

## Status

⏳ **TODO** - To be implemented.

## Implementation Details

### Similar to Codebase Search Tool

This tool can use similar logic to the Codebase Search Tool (2.10), leveraging the existing `VectorSearch/` infrastructure.

### Workflow (Similar to Codebase Search)

1. **Read Documentation Files** - Read documentation files (markdown, HTML, text, etc.)
2. **Send to LLM** - Send file content to LLM for analysis/summarization
3. **Get Markdown Summary** - LLM returns markdown summary of the documentation
4. **Generate Vectors** - Generate embedding vectors from the summary using LLM embedding API
5. **Insert into Database** - Store vectors in FAISS index

### SQL Database Requirements

Similar to Codebase Search Tool, need an SQL database to store metadata:
- **Vector positions** - Reference to vectors in FAISS index
- **File path** - Path to the indexed documentation file
- **Current status** - Status of the file (indexed, needs update, etc.)
- **Timestamp** - When the file was last indexed/updated
- **File hash/checksum** - To detect when file has changed and needs re-indexing

This allows the system to:
- Track which documentation files are indexed
- Know when to renew/update documentation (when file changes)
- Maintain file status and metadata separate from vector storage

### Features
- Index documentation files
- Search documentation using FAISS vectors
- Make documentation available to LLM context
- Documentation browsing UI
- Support multiple documentation sources
- File change detection and re-indexing

### Use Cases
- Project documentation
- API documentation
- Code comments
- External documentation
- README files
- Wiki pages

### Files to Create/Modify
- `liboctools/DocumentationIndexingTool.vala` (to be created, namespace: `OLLMtools`)
- Documentation indexer (similar to CodeIndexer)
- Integration with `VectorSearch/` directory components
- SQL database schema for documentation metadata

### Implementation Notes
- Reuse VectorSearch infrastructure (FAISS, Database, Index)
- Similar workflow to Codebase Search Tool
- Support various documentation formats (markdown, HTML, text, etc.)
- Handle large documentation sets efficiently
- Implemented as a tool in the tool system
- Track documentation file changes for re-indexing

## Repository System for Shared Databases

### Overview

To make documentation indexing more efficient and enable sharing of pre-indexed resources, the system should support a repository-based approach where:

1. **Documentation Repositories** - Collections of documentation files that can be downloaded
2. **Pre-generated Databases** - SQLite databases with metadata already indexed
3. **Pre-generated Vector Indexes** - FAISS vector indexes with embeddings already computed
4. **Shared Resources** - Codebases and databases that can be restored from an online service

### Architecture

The repository system would work similarly for both codebase search and documentation indexing:

#### Storage Components (Per Repository)

1. **FAISS Vector Index** (`.faiss.vectors` file)
   - Pre-computed vector embeddings
   - Can be downloaded and used directly
   - No re-indexing required

2. **SQLite Metadata Database** (`.sqlite` or `.db` file)
   - Pre-computed metadata mapping (vector_id → file locations)
   - Includes file paths, line ranges, element types, etc.
   - Can be downloaded and restored

3. **Source Files** (optional, for documentation repositories)
   - Original documentation files
   - May be included in repository or referenced externally
   - Needed for displaying search results

#### Repository Structure

```
repository-name/
├── manifest.json          # Repository metadata, version, dependencies
├── index.faiss.vectors    # FAISS vector index
├── metadata.sqlite        # SQLite metadata database
├── files/                 # Source files (optional)
│   ├── doc1.md
│   ├── doc2.html
│   └── ...
└── checksums.json         # File integrity verification
```

#### Repository Manifest Format

```json
{
  "name": "gtk4-documentation",
  "version": "4.14.0",
  "description": "GTK4 API documentation",
  "type": "documentation",
  "embedding_model": "text-embedding-ada-002",
  "embedding_dimension": 1536,
  "indexed_at": "2024-01-15T10:30:00Z",
  "files": {
    "index": "index.faiss.vectors",
    "metadata": "metadata.sqlite",
    "source_dir": "files/"
  },
  "dependencies": {
    "ollmchat_version": ">=2.13.0"
  }
}
```

### Features

#### 1. Repository Registry

- Online service or local registry listing available repositories
- Search and browse available documentation/codebase indexes
- Version tracking and updates

#### 2. Download & Restore

- Download repository packages (FAISS index + SQLite database)
- Restore into local system at specified data directory
- Verify integrity using checksums
- Handle version conflicts and updates

#### 3. Local Repository Management

- List installed repositories
- Check for updates
- Remove/uninstall repositories
- Manage repository locations and paths

#### 4. Integration with Existing Tools

- Codebase Search Tool can use shared codebase indexes
- Documentation Indexing Tool can use shared documentation indexes
- Both tools can work with local or shared indexes transparently

### Implementation Requirements

#### New Components

1. **Repository Manager** (`liboctools/RepositoryManager.vala`)
   - Download repositories from online service
   - Restore databases and indexes to local system
   - Manage repository lifecycle (install, update, remove)
   - Verify repository integrity

2. **Repository Registry Client** (`liboctools/RepositoryRegistry.vala`)
   - Query online registry for available repositories
   - Search and filter repositories
   - Get repository metadata and download URLs

3. **Database Import/Export** (extend existing `libocsqlite/Database.vala`)
   - Export database to file for sharing
   - Import database from file
   - Merge databases (for combining multiple repositories)

4. **FAISS Index Import/Export** (extend `libocvector/Index.vala`)
   - Export FAISS index to file
   - Import FAISS index from file
   - Verify index compatibility (dimension matching)

#### Database Schema Extensions

Add repository tracking to metadata databases:

```sql
CREATE TABLE repositories (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    version TEXT NOT NULL,
    type TEXT NOT NULL,  -- 'documentation' or 'codebase'
    source_url TEXT,
    installed_at TIMESTAMP,
    updated_at TIMESTAMP,
    data_dir TEXT,  -- Where repository is installed
    UNIQUE(name, version)
);
```

#### File Structure

- `liboctools/RepositoryManager.vala` - Main repository management
- `liboctools/RepositoryRegistry.vala` - Online registry client
- `liboctools/RepositoryManifest.vala` - Manifest parsing/validation
- Extend `libocsqlite/Database.vala` - Add import/export methods
- Extend `libocvector/Index.vala` - Add import/export methods
- Extend `libocvector/Database.vala` - Add repository-aware initialization

### Use Cases

1. **Popular Documentation Sets**
   - GTK4 API documentation
   - Python standard library docs
   - Linux man pages
   - Language reference manuals

2. **Popular Codebases**
   - Well-known open source projects
   - Framework codebases
   - Library source code

3. **Team/Organization Sharing**
   - Internal documentation indexes
   - Company codebase indexes
   - Shared project documentation

4. **Offline/Disconnected Use**
   - Download repositories when online
   - Use pre-indexed databases offline
   - No need for LLM API calls during indexing

### Benefits

1. **Performance** - No need to re-index large documentation sets
2. **Cost Savings** - Avoid embedding API costs for shared resources
3. **Consistency** - Everyone uses the same indexed version
4. **Speed** - Instant access to pre-indexed resources
5. **Sharing** - Easy distribution of indexed documentation/codebases

### Future Enhancements

- Incremental updates (download only changed files)
- Repository caching and CDN support
- User-contributed repositories
- Repository ratings and reviews
- Automatic updates and notifications
