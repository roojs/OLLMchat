# OLLMchat

## Summary

OLLMchat is a work-in-progress library and embeddable widget that provides LLM access and tool integration for applications. The project focuses on Vala and GTK4, with the main library written in pure Vala.

- **Libraries** - A set of libraries for LLM access, tool integration, and markdown processing
  - `libomarkdown.so` - Markdown parsing and rendering library (no GTK dependencies)
  - `libomarkdown-ui.so` - Markdown GTK rendering library (depends on libomarkdown, includes GTK components)
  - `libollmchat.so` - Base library for Ollama/OpenAI API access (depends on libomarkdown, no GTK dependencies)
  - `libollmchat-ui.so` - UI library with chat widgets (depends on libollmchat and libomarkdown-ui, includes GTK components)
- **Technology Stack** - Written in pure Vala, focusing on Vala and GTK4
- **Tool Dependencies** - Some tools will rely on third-party applications (e.g., semantic code search which is in another repository)
- **Tool Calling** - Supports tool calling functionality
- **Permission System** - Includes a permission system for secure tool access
- **Prompt Manipulation** - Provides prompt manipulation capabilities
- **Generation** - Supports text generation from LLM models
- **Sample Tools** - Includes working tools: ReadFile, EditFile, RunTerminalCommand
- **Embeddable Widget** - Reusable chat widget (`ChatWidget`) that can be embedded in applications
- **Current Status** - Builds four shared libraries with headers, VAPI, and GIR files. Includes test executables (`test-ollama`, `test-window`, and `test-markdown-parser`)

## Demo

<video src="https://private-user-images.githubusercontent.com/415282/517941034-0182399e-5418-4dd7-a03e-f6cdc34c7f23.mp4?jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3NjM5NTcwMTksIm5iZiI6MTc2Mzk1NjcxOSwicGF0aCI6Ii80MTUyODIvNTE3OTQxMDM0LTAxODIzOTllLTU0MTgtNGRkNy1hMDNlLWY2Y2RjMzRjN2YyMy5tcDQ_WC1BbXotQWxnb3JpdGhtPUFXUzQtSE1BQy1TSEEyNTYmWC1BbXotQ3JlZGVudGlhbD1BS0lBVkNPRFlMU0E1M1BRSzRaQSUyRjIwMjUxMTI0JTJGdXMtZWFzdC0xJTJGczMlMkZhd3M0X3JlcXVlc3QmWC1BbXotRGF0ZT0yMDI1MTEyNFQwMzU4MzlaJlgtQW16LUV4cGlyZXM9MzAwJlgtQW16LVNpZ25hdHVyZT03OTU1YjNlMzcyNDg3MDQ1YmZhNjIzNjNlNzY0ZmEzNjViOGU0YTMwNDI1ZjI1YzYzNGQwOGQzZmMwMTVmMTk0JlgtQW16LVNpZ25lZEhlYWRlcnM9aG9zdCJ9.iz1emltCz5popYA1xYMVceSQeBQTciSBlvhx9mT-wdM" controls width="100%"></video>

**Note:** If the video doesn't display above, you can [watch it directly here](https://private-user-images.githubusercontent.com/415282/517941034-0182399e-5418-4dd7-a03e-f6cdc34c7f23.mp4?jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3NjM5NTcwMTksIm5iZiI6MTc2Mzk1NjcxOSwicGF0aCI6Ii80MTUyODIvNTE3OTQxMDM0LTAxODIzOTllLTU0MTgtNGRkNy1hMDNlLWY2Y2RjMzRjN2YyMy5tcDQ_WC1BbXotQWxnb3JpdGhtPUFXUzQtSE1BQy1TSEEyNTYmWC1BbXotQ3JlZGVudGlhbD1BS0lBVkNPRFlMU0E1M1BRSzRaQSUyRjIwMjUxMTI0JTJGdXMtZWFzdC0xJTJGczMlMkZhd3M0X3JlcXVlc3QmWC1BbXotRGF0ZT0yMDI1MTEyNFQwMzU4MzlaJlgtQW16LUV4cGlyZXM9MzAwJlgtQW16LVNpZ25hdHVyZT03OTU1YjNlMzcyNDg3MDQ1YmZhNjIzNjNlNzY0ZmEzNjViOGU0YTMwNDI1ZjI1YzYzNGQwOGQzZmMwMTVmMTk0JlgtQW16LVNpZ25lZEhlYWRlcnM9aG9zdCJ9.iz1emltCz5popYA1xYMVceSQeBQTciSBlvhx9mT-wdM).

## Documentation

Online API documentation is available:

- **[ollmchat API Reference](https://roojs.github.io/OLLMchat/ollmchat/ollmchat/index.htm)** - Unified library documentation (base and UI)

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
- `libomarkdown.so` - Markdown parsing library (with headers, VAPI, and GIR files)
- `libomarkdown-ui.so` - Markdown GTK rendering library (with headers, VAPI, and GIR files)
- `libollmchat.so` - Base library for LLM API access (with headers, VAPI, and GIR files)
- `libollmchat-ui.so` - UI library with chat widgets (with headers, VAPI, and GIR files)
- `test-ollama` - Command-line test executable
- `test-window` - GTK UI test executable
- `test-markdown-parser` - Markdown parser test executable
- Valadoc documentation (in `docs/ollmchat/`)

## Project Structure

**Markdown Libraries:**
- `Markdown/` - Markdown parsing and rendering (libomarkdown, namespace: `Markdown`)
- `MarkdownGtk/` - GTK-specific markdown rendering (libomarkdown-ui, namespace: `MarkdownGtk`)

**OLLMchat Base Library (`libollmchat.so`):**
- `OLLMchat/` - Main namespace (`OLLMchat`)
  - `Client.vala` - Main client class for Ollama/OpenAI API access
  - `Call/` - API call implementations (Chat, Embed, Generate, etc.)
  - `Response/` - Response handling classes
  - `Tool/` - Tool interface and base classes (namespace: `OLLMchat.Tool`)
  - `Tools/` - Tool implementations (ReadFile, EditMode, RunCommand, etc., namespace: `OLLMchat.Tools`)
  - `ChatPermission/` - Permission system for tool access control (namespace: `OLLMchat.ChatPermission`)
  - `Prompt/` - Prompt generation system for different agent types (namespace: `OLLMchat.Prompt`)
  - `Message.vala`, `MessageInterface.vala`, `OllamaBase.vala` - Core message and base classes

**OLLMchat UI Library (`libollmchat-ui.so`):**
- `OLLMchatGtk/` - GTK UI components (namespace: `OLLMchatGtk`)
  - `ChatWidget.vala` - Main chat widget
  - `ChatView.vala` - Chat view component
  - `ChatInput.vala` - Chat input component
  - `ChatPermission.vala` - Permission UI component
  - `Tools/` - GTK-specific tool UI components (namespace: `OLLMchatGtk.Tools`)
    - `Permission.vala` - Permission provider UI
    - `RunCommand.vala` - Run command tool UI

**Resources and Documentation:**
- `resources/` - Resource files including prompt templates
- `docs/` - Generated documentation (Valadoc) and implementation plans

## Dependencies

**Markdown base library (`libomarkdown.so`)**:
- Gee
- GLib/GIO
- libxml-2.0

**Markdown UI library (`libomarkdown-ui.so`)**:
- All markdown base library dependencies
- GTK4

**OLLMchat base library (`libollmchat.so`)**:
- All markdown base library dependencies
- json-glib
- libsoup-3.0

**OLLMchat UI library (`libollmchat-ui.so`)**:
- All OLLMchat base library dependencies
- All markdown UI library dependencies
- gtksourceview-5

**Test executables**:
- All dependencies above (test-window and test-markdown-parser require GTK4 and gtksourceview-5)

## License

This project is licensed under the GNU Lesser General Public License version 3.0 (LGPL-3.0). See the [LICENSE](LICENSE) file for details.


## Notes

- The build system uses Meson and Ninja
- Resources are compiled into the binary using GLib's resource system
- The prompt system loads agent-specific sections from resource files
- Libraries are built as shared libraries with C headers, VAPI files, and GObject Introspection (GIR) files
- Markdown functionality is split into separate libraries (libomarkdown and libomarkdown-ui) for better modularity
- Valadoc documentation is automatically generated in `docs/ollmchat/` (unified documentation for all libraries)

