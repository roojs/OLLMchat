# OLLMchat

<div align="center">
  <img src="https://raw.githubusercontent.com/roojs/OLLMchat/fdae4de262289db49def51443d6b28be06b9eece/pixmaps/scalable/apps/org.roojs.ollmchat.svg" alt="OLLMchat Logo" width="200">
</div>

## Summary

OLLMchat is a work-in-progress library and embeddable widget that provides LLM access and tool integration for applications. The project focuses on Vala and GTK4, with the main library written in pure Vala.

- **Libraries** - A set of libraries for LLM access, tool integration, and markdown processing
  - `libocmarkdown.so` - Markdown parsing and rendering library (no GTK dependencies)
  - `libocmarkdowngtk.so` - Markdown GTK rendering library (depends on libocmarkdown, includes GTK components)
  - `libocsqlite.so` - SQLite query builder library (no GTK dependencies)
  - `libollmchat.so` - Base library for Ollama/OpenAI API access (depends on libocsqlite, no GTK dependencies)
  - `libollmchatgtk.so` - GTK library with chat widgets (depends on libollmchat, libocmarkdown, libocmarkdowngtk, libocsqlite, includes GTK components)
- **Technology Stack** - Written in pure Vala, focusing on Vala and GTK4
- **Tool Dependencies** - Some tools will rely on third-party applications (e.g., semantic code search which is in another repository)
- **Tool Calling** - Supports tool calling functionality
- **Permission System** - Includes a permission system for secure tool access
- **Prompt Manipulation** - Provides prompt manipulation capabilities
- **Generation** - Supports text generation from LLM models
- **Sample Tools** - Includes working tools: ReadFile, EditMode, RunCommand
- **Embeddable Widget** - Reusable chat widget (`ChatWidget`) that can be embedded in applications
- **Current Status** - Builds five shared libraries with headers, VAPI, and GIR files. Includes the main `ollmchat` application, test executables (`oc-test-cli`, `oc-markdown-test`, `oc-html2md`) and example tools (`oc-md2html`)

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
- `libocmarkdown.so` - Markdown parsing library (with headers, VAPI, and GIR files)
- `libocmarkdowngtk.so` - Markdown GTK rendering library (with headers, VAPI, and GIR files)
- `libocsqlite.so` - SQLite query builder library (with headers, VAPI, and GIR files)
- `libollmchat.so` - Base library for LLM API access (with headers, VAPI, and GIR files)
- `libollmchatgtk.so` - GTK library with chat widgets (with headers, VAPI, and GIR files)
- `ollmchat` - Main application executable
- `oc-test-cli` - Command-line test executable
- `oc-markdown-test` - Markdown parser test executable
- `oc-html2md` - HTML to Markdown converter (reads from stdin)
- `oc-md2html` - Markdown to HTML converter (takes file as argument)
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
```

The wrapper scripts are automatically generated during the build process and set up the library paths correctly. Note that only `ollmchat` has a `.bin` wrapper; the other executables can be run directly from the build directory.

## Project Structure

The project is organized into component directories, each with its own `meson.build` file:

**Markdown Libraries:**
- `libocmarkdown/` - Markdown parsing and rendering (libocmarkdown.so, namespace: `Markdown`)
- `libocmarkdowngtk/` - GTK-specific markdown rendering (libocmarkdowngtk.so, namespace: `MarkdownGtk`)

**SQLite Library:**
- `libocsqlite/` - SQLite query builder (libocsqlite.so, namespace: `SQ`)

**OLLMchat Base Library (`libollmchat.so`):**
- `libollmchat/` - Main namespace (`OLLMchat`)
  - `Client.vala` - Main client class for Ollama/OpenAI API access
  - `Call/` - API call implementations (Chat, Embed, Generate, etc.)
  - `Response/` - Response handling classes
  - `Tool/` - Tool interface and base classes (namespace: `OLLMchat.Tool`)
  - `Tools/` - Tool implementations (ReadFile, EditMode, RunCommand, etc., namespace: `OLLMchat.Tools`)
  - `ChatPermission/` - Permission system for tool access control (namespace: `OLLMchat.ChatPermission`)
  - `Prompt/` - Prompt generation system for different agent types with agent management (namespace: `OLLMchat.Prompt`)
  - `History/` - Chat history management (namespace: `OLLMchat.History`)
  - `Message.vala`, `ChatContentInterface.vala`, `OllamaBase.vala` - Core message and base classes

**OLLMchat GTK Library (`libollmchatgtk.so`):**
- `libollmchatgtk/` - GTK UI components (namespace: `OLLMchatGtk`)
  - `ChatWidget.vala` - Main chat widget
  - `ChatView.vala` - Chat view component
  - `ChatInput.vala` - Chat input component
  - `ChatPermission.vala` - Permission UI component
  - `HistoryBrowser.vala` - History browser component
  - `Tools/` - GTK-specific tool UI components (namespace: `OLLMchatGtk.Tools`)
    - `Permission.vala` - Permission provider UI
    - `RunCommand.vala` - Run command tool UI

**Other Directories:**
- `examples/` - Example programs and test code (each with its own meson.build)
- `docs/` - Generated documentation (Valadoc) and implementation plans
- `resources/` - Resource files including prompt templates
- `vapi/` - VAPI files for external dependencies

## Dependencies

**Markdown base library (`libocmarkdown.so`)**:
- Gee
- GLib/GIO
- libxml-2.0
- libsoup-3.0
- json-glib

**Markdown GTK library (`libocmarkdowngtk.so`)**:
- All markdown base library dependencies
- GTK4
- gtksourceview-5

**SQLite library (`libocsqlite.so`)**:
- Gee
- GLib/GIO
- sqlite3

**OLLMchat base library (`libollmchat.so`)**:
- Gee
- GLib/GIO
- json-glib
- libsoup-3.0
- libocsqlite (depends on libocsqlite.so)

**OLLMchat GTK library (`libollmchatgtk.so`)**:
- All OLLMchat base library dependencies
- All markdown GTK library dependencies
- GTK4
- gtksourceview-5
- libadwaita-1 (for test executables)

**Test executables**:
- All dependencies above (ollmchat and oc-markdown-test require GTK4, gtksourceview-5, and libadwaita-1)

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

