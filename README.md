# OLLMchat

<div align="center">
  <img src="https://raw.githubusercontent.com/roojs/OLLMchat/fdae4de262289db49def51443d6b28be06b9eece/pixmaps/scalable/apps/org.roojs.ollmchat.svg" alt="OLLMchat Logo" width="200">
</div>

## Summary

OLLMchat is a work-in-progress AI application for interacting with LLMs (Large Language Models) such as Ollama and OpenAI, featuring a full-featured chat interface with code assistant capabilities including semantic codebase search. The project is built as a modular set of reusable libraries that can be integrated into other applications, with the main application serving as a complete AI chat client. The project focuses on Vala and GTK4, with all libraries written in pure Vala.

- **Main Application (`ollmchat`)** - A complete AI chat client with:
  - Full-featured chat interface for interacting with LLMs (Ollama/OpenAI)
  - Settings dialog with model search and download from Ollama
  - Code assistant agent with semantic codebase search capabilities
  - Chat history management with session browser
  - Tool integration: ReadFile, EditMode, RunCommand, WebFetch, and CodebaseSearch (semantic search)
  - Project management and file tracking
  - Permission system for secure tool access
  - Support for multiple agent types (Just Ask, Code Assistant)
- **Libraries** - A set of reusable libraries for LLM access, tool integration, and markdown processing
  - `libocagent.so` - Base agent library for AI agent functionality
  - `libocmarkdown.so` - Markdown parsing and rendering library (no GTK dependencies)
  - `libocmarkdowngtk.so` - Markdown GTK rendering library (includes GTK components)
  - `libocsqlite.so` - SQLite query builder library (no GTK dependencies)
  - `libocfiles.so` - File and project management library (no GTK dependencies)
  - `liboccoder.so` - Code editor and project management library (includes GTK components)
  - `libocvector.so` - Semantic codebase search library using vector embeddings and FAISS (no GTK dependencies)
  - `libollmchat.so` - Base library for Ollama/OpenAI API access (no GTK dependencies)
  - `liboctools.so` - Tools library for file operations and utilities (no GTK dependencies)
  - `libollmchatgtk.so` - GTK library with chat widgets (includes GTK components)
- **Example Tools** - Command-line utilities demonstrating library capabilities:
  - `oc-test-cli` - Test tool for LLM API calls (models, chat, streaming)
  - `oc-test-files` - Test tool for file operations (read/write files with line ranges, project management, buffer operations, backups)
  - `oc-markdown-test` - Markdown parser test tool (parses markdown and outputs callback trace)
  - `oc-html2md` - HTML to Markdown converter (reads HTML from stdin, outputs Markdown)
  - `oc-md2html` - Markdown to HTML converter (converts markdown file to HTML)
  - `oc-diff` - Unified diff tool (compares two files and outputs differences in unified diff format)
  - `oc-vector-index` - Codebase indexing tool for semantic search (indexes files/folders using tree-sitter and vector embeddings)
  - `oc-vector-search` - Command-line semantic code search tool (searches indexed codebase by semantic meaning)
  - `oc-migrate-editors` - Project migration tool (migrates projects from Cursor editor configuration)
  - `oc-test-fetch` - Web fetch test tool (fetches web content from URLs with format conversion support)
- **Technology Stack** - Written in pure Vala, focusing on Vala and GTK4
- **Tool Dependencies** - Some tools will rely on third-party applications
- **Tool Calling** - Supports tool calling functionality
- **Permission System** - Includes a permission system for secure tool access
- **Prompt Manipulation** - Provides prompt manipulation capabilities
- **Generation** - Supports text generation from LLM models
- **Embeddable Widget** - Reusable chat widget (`ChatWidget`) that can be embedded in applications

## Demo

<video src="https://private-user-images.githubusercontent.com/415282/524658129-c8c8dba0-86df-46ff-bdb5-0773ced236da.mp4?jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3NjUzNDYyNjMsIm5iZiI6MTc2NTM0NTk2MywicGF0aCI6Ii80MTUyODIvNTI0NjU4MTI5LWM4YzhkYmEwLTg2ZGYtNDZmZi1iZGI1LTA3NzNjZWQyMzZkYS5tcDQ_WC1BbXotQWxnb3JpdGhtPUFXUzQtSE1BQy1TSEEyNTYmWC1BbXotQ3JlZGVudGlhbD1BS0lBVkNPRFlMU0E1M1BRSzRaQSUyRjIwMjUxMjEwJTJGdXMtZWFzdC0xJTJGczMlMkZhd3M0X3JlcXVlc3QmWC1BbXotRGF0ZT0yMDI1MTIxMFQwNTUyNDNaJlgtQW16LUV4cGlyZXM9MzAwJlgtQW16LVNpZ25hdHVyZT1kN2QwOGRhNWVjZjM0ZDlkMDI0ZmVmY2EzM2ZkZjYyYzJlOGFmNjc1ODBkMDMzZGE5MDVkNTAyNjEzMDgzNGYyJlgtQW16LVNpZ25lZEhlYWRlcnM9aG9zdCJ9.GPlCLeqcdphew7wCeMQ5o29_kt9SW8Fiq3WhSJw_-54" controls width="100%"></video>

**Note:** If the video doesn't display above, you can [watch it directly here](https://private-user-images.githubusercontent.com/415282/524658129-c8c8dba0-86df-46ff-bdb5-0773ced236da.mp4?jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3NjUzNDYyNjMsIm5iZiI6MTc2NTM0NTk2MywicGF0aCI6Ii80MTUyODIvNTI0NjU4MTI5LWM4YzhkYmEwLTg2ZGYtNDZmZi1iZGI1LTA3NzNjZWQyMzZkYS5tcDQ_WC1BbXotQWxnb3JpdGhtPUFXUzQtSE1BQy1TSEEyNTYmWC1BbXotQ3JlZGVudGlhbD1BS0lBVkNPRFlMU0E1M1BRSzRaQSUyRjIwMjUxMjEwJTJGdXMtZWFzdC0xJTJGczMlMkZhd3M0X3JlcXVlc3QmWC1BbXotRGF0ZT0yMDI1MTIxMFQwNTUyNDNaJlgtQW16LUV4cGlyZXM9MzAwJlgtQW16LVNpZ25hdHVyZT1kN2QwOGRhNWVjZjM0ZDlkMDI0ZmVmY2EzM2ZkZjYyYzJlOGFmNjc1ODBkMDMzZGE5MDVkNTAyNjEzMDgzNGYyJlgtQW16LVNpZ25lZEhlYWRlcnM9aG9zdCJ9.GPlCLeqcdphew7wCeMQ5o29_kt9SW8Fiq3WhSJw_-54).

## Documentation

Online API documentation is available:

- **[ollmchat API Reference](https://roojs.github.io/OLLMchat/ollmchat/ollmchat/index.htm)** - Unified library documentation (base and UI)

Implementation plans and roadmap:

- **[Implementation Plans Summary](docs/plans/1.0-summary.md)** - Overview of all planned features with status indicators

## Build Instructions

This directory contains the OLLMchat library and test applications for working with Ollama API and prompt generation.

## Dependencies

Before building, install the required dependencies. On Debian/Ubuntu systems:

```bash
sudo apt install \
  meson \
  ninja-build \
  valac \
  libgee-0.8-dev \
  libglib2.0-dev \
  libgtk-4-dev \
  libgtksourceview-5-dev \
  libadwaita-1-dev \
  libsoup-3.0-dev \
  libjson-glib-dev \
  libxml2-dev \
  libsqlite3-dev \
  libfaiss-dev \
  pkg-config
```

**For code search functionality**, you'll also need:

- **Tree-sitter language parsers**: Install tree-sitter parsers for the languages you want to index. A script is available at `docs/tools/tree-sitter-packages.php` to generate Debian packages for tree-sitter language parsers from GitHub repositories.

- **Ollama models**: For vector search to work, you need to have the following models available in Ollama:
  - `bge-m3:latest` - For generating embeddings
  - `qwen3-coder:30b` - For code analysis and description generation

You can download these models through the settings dialog in the application, or manually using:
```bash
ollama pull bge-m3:latest
ollama pull qwen3-coder:30b
```

## Building

To build the project, follow these steps:

### 1. Setup the build directory

From the project root directory, run:

```bash
meson setup build --prefix=/usr
```

This will configure the build system with Meson and set the installation prefix to `/usr`.

### 2. Compile the project

After setup, compile the project using:

```bash
ninja -C build
```

This will build:
- `libocagent.so` - Base agent library (with headers, VAPI, and GIR files)
- `libocmarkdown.so` - Markdown parsing library (with headers, VAPI, and GIR files)
- `libocmarkdowngtk.so` - Markdown GTK rendering library (with headers, VAPI, and GIR files)
- `libocsqlite.so` - SQLite query builder library (with headers, VAPI, and GIR files)
- `libocfiles.so` - File and project management library (with headers, VAPI, and GIR files)
- `liboccoder.so` - Code editor and project management library (with headers, VAPI, and GIR files)
- `libocvector.so` - Semantic codebase search library (with headers, VAPI, and GIR files)
- `libollmchat.so` - Base library for LLM API access (with headers, VAPI, and GIR files)
- `liboctools.so` - Tools library for file operations and utilities (with headers, VAPI, and GIR files)
- `libollmchatgtk.so` - GTK library with chat widgets (with headers, VAPI, and GIR files)
- `ollmchat` - Main application executable
- `oc-test-cli` - Command-line test executable
- `oc-markdown-test` - Markdown parser test executable
- `oc-html2md` - HTML to Markdown converter (reads from stdin)
- `oc-md2html` - Markdown to HTML converter (takes file as argument)
- `oc-diff` - Unified diff tool (compares two files and outputs differences)
- `oc-vector-index` - Vector indexing tool for codebase search (indexes files/folders for semantic search)
- `oc-vector-search` - Command-line semantic code search tool
- `oc-migrate-editors` - Project migration tool
- `oc-test-fetch` - Web fetch test tool (fetches web content from URLs)
- Valadoc documentation (in `docs/ollmchat/`)

### 3. Running executables without installing

The executables are configured with `build_rpath` so they can find the libraries in the build directory without needing to install them. Wrapper scripts are automatically created in the top-level `build/` directory for easy access:

```bash
# Run from top-level build directory
# Note: For testing uninstalled, use the executables directly
./build/ollmchat.bin
./build/oc-test-cli --help
./build/oc-markdown-test
./build/oc-html2md
./build/oc-md2html
./build/oc-diff file1.txt file2.txt
./build/oc-vector-index --help
./build/oc-vector-search --help
./build/oc-test-fetch https://example.com
```

The wrapper scripts are automatically generated during the build process and set up the library paths correctly. Note that only `ollmchat` has a `.bin` wrapper; the other executables can be run directly from the build directory.

## Project Structure

The project is organized into component directories, each with its own `meson.build` file:

**Markdown Libraries:**
- `libocmarkdown/` - Markdown parsing and rendering (libocmarkdown.so, namespace: `Markdown`)
- `libocmarkdowngtk/` - Embeddable widget for rendering markdown using GtkTextView and GtkSourceView (libocmarkdowngtk.so, namespace: `MarkdownGtk`)

**SQLite Library:**
- `libocsqlite/` - SQLite query builder (libocsqlite.so, namespace: `SQ`)

**Agent Library (`libocagent.so`):**
- `libocagent/` - Base agent library for AI agent functionality (libocagent.so, namespace: `OLLMagent`)
  - `BaseAgent.vala` - Base agent class
  - `JustAsk.vala` - Simple "just ask" agent implementation

**File Management Library (`libocfiles.so`):**
- `libocfiles/` - File and project management (libocfiles.so, namespace: `OLLMfiles`)
  - Provides file tracking and project management without GTK/git dependencies
  - Used by `libocvector` for file operations
  - `File.vala`, `FileBase.vala`, `FileAlias.vala`, `FileBuffer.vala`, `FileChange.vala` - File classes
  - `Folder.vala`, `FolderFiles.vala` - Folder classes
  - `ProjectFile.vala`, `ProjectFiles.vala`, `ProjectList.vala`, `ProjectManager.vala`, `ProjectMigrate.vala` - Project management
  - `BufferProvider.vala`, `BufferProviderBase.vala`, `DummyFileBuffer.vala` - Buffer providers
  - `GitProvider.vala`, `GitProviderBase.vala` - Git provider classes
  - `Diff/` - Diff and patch utilities (Differ.vala, Patch.vala, PatchApplier.vala)

**Code Editor Library (`liboccoder.so`):**
- `liboccoder/` - Code editor and project management (liboccoder.so, namespace: `OLLMcoder`)
  - `SourceView.vala` - Code editor component with syntax highlighting
  - `GtkSourceFileBuffer.vala` - GTK SourceView buffer implementation
  - `BufferProvider.vala`, `GitProvider.vala` - Buffer and git providers for GTK contexts
  - `SearchableDropdown.vala`, `ProjectDropdown.vala`, `FileDropdown.vala` - Dropdown widgets
  - `Prompt/CodeAssistant.vala` - Code assistant agent with semantic search capabilities
    - The code assistant can perform semantic codebase search using the vector indexing system
    - Includes an indexer tool (`oc-vector-index`) for indexing codebases to enable semantic search
    - Semantic search allows finding code elements by meaning rather than just text matching

**Vector Search Library (`libocvector.so`):**
- `libocvector/` - Semantic codebase search using vector embeddings and FAISS (libocvector.so, namespace: `OLLMvector`)
  - **Status**: Mostly complete - Provides semantic code search capabilities by indexing code elements (classes, methods, functions, etc.) using tree-sitter AST parsing, LLM analysis for descriptions, and FAISS for vector similarity search
  - `Index.vala` - FAISS vector index integration
  - `Database.vala` - Vector database with embeddings storage
  - `VectorMetadata.vala` - Metadata storage (SQL database) mapping vector IDs to code locations
  - `Indexing/` - Code indexing components (namespace: `OLLMvector.Indexing`)
    - `Tree.vala` - Tree-sitter AST parsing and code element extraction
    - `Analysis.vala` - LLM-based code analysis and description generation
    - `VectorBuilder.vala` - Vector generation and FAISS storage
    - `Indexer.vala` - Main indexing orchestrator for files and folders
  - `Search/` - Search components (namespace: `OLLMvector.Search`)
    - `Search.vala` - Vector similarity search execution
    - `SearchResult.vala` - Search result representation
  - `Tool/` - Tool integration (namespace: `OLLMvector.Tool`)
    - `CodebaseSearchTool.vala` - Tool interface for semantic codebase search
    - `RequestCodebaseSearch.vala` - Request handling for codebase search tool
  - Uses `libocfiles` (OLLMfiles namespace) for file tracking and project management
  - Example tool: `oc-vector-index` - Command-line tool for indexing files/folders
  - **Tree-sitter Language Support**: A script is available at `docs/tools/tree-sitter-packages.php` to generate Debian packages for tree-sitter language parsers. This script automates building Debian packages for various tree-sitter parsers from GitHub repositories, making it easy to install language support for the vector indexing system.

**OLLMchat Base Library (`libollmchat.so`):**
- `libollmchat/` - Main namespace (`OLLMchat`)
  - `Client.vala` - Main client class for Ollama/OpenAI API access
  - `Call/` - API call implementations (Chat, Embed, Generate, etc.)
  - `Response/` - Response handling classes
  - `Tool/` - Tool interface and base classes (namespace: `OLLMchat.Tool`)
  - `ChatPermission/` - Permission system for tool access control (namespace: `OLLMchat.ChatPermission`)
  - `Prompt/` - Prompt generation system for different agent types with agent management (namespace: `OLLMchat.Prompt`)
  - `History/` - Chat history management (namespace: `OLLMchat.History`)
  - `Message.vala`, `ChatContentInterface.vala`, `OllamaBase.vala` - Core message and base classes

**Tools Library (`liboctools.so`):**
- `liboctools/` - Tools for file operations and utilities (namespace: `OLLMtools`)
  - `ReadFile.vala`, `RequestReadFile.vala` - File reading tool with line range support
  - `EditMode.vala`, `RequestEditMode.vala`, `EditModeChange.vala` - File editing tool
  - `RunCommand.vala`, `RequestRunCommand.vala` - Terminal command execution tool
  - `WebFetchTool.vala`, `RequestWebFetch.vala` - Web content fetching tool
  - Tools have access to `ProjectManager` for project context awareness
  - Files in active project automatically skip permission prompts

**OLLMchat GTK Library (`libollmchatgtk.so`):**
- `libollmchatgtk/` - GTK UI components (namespace: `OLLMchatGtk`)
  - `ChatWidget.vala` - Main chat widget
  - `ChatView.vala` - Chat view component
  - `ChatInput.vala` - Chat input component
  - `ChatPermission.vala` - Permission UI component
  - `HistoryBrowser.vala` - History browser component
  - `Message.vala`, `ClipboardManager.vala`, `ClipboardMetadata.vala` - Supporting components

**Other Directories:**
- `examples/` - Example programs and test code (each with its own meson.build)
- `docs/` - Generated documentation (Valadoc) and implementation plans
- `resources/` - Resource files including prompt templates
- `vapi/` - VAPI files for external dependencies

## License

This project is licensed under the GNU Lesser General Public License version 3.0 (LGPL-3.0). See the [LICENSE](LICENSE) file for details.


## Notes

- The build system uses Meson and Ninja with a modular structure
- Each library component has its own directory with its own `meson.build` file
- Resources are compiled into the binary using GLib's resource system
- The prompt system loads agent-specific sections from resource files
- Libraries are built as shared libraries with C headers, VAPI files, and GObject Introspection (GIR) files
- Markdown functionality is split into separate libraries (libocmarkdown and libocmarkdowngtk) for better modularity
- SQLite functionality is in a separate library (libocsqlite) for reuse
- Valadoc documentation is automatically generated in `docs/ollmchat/` (unified documentation for all libraries)
- Build order is managed automatically by Meson based on dependencies

