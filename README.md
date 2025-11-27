# OLLMchat

## Summary

OLLMchat is a work-in-progress library and embeddable widget that provides LLM access and tool integration for applications. The project focuses on Vala and GTK4, with the main library written in pure Vala.

- **Library** - A library that can talk to Ollama and most OpenAI-compatible REST interfaces
  - `libollmchat.so` - Base library (no GTK dependencies)
  - `libollmchat-ui.so` - UI library (depends on base library, includes GTK components)
- **Technology Stack** - Written in pure Vala, focusing on Vala and GTK4
- **Tool Dependencies** - Some tools will rely on third-party applications (e.g., semantic code search which is in another repository)
- **Tool Calling** - Supports tool calling functionality
- **Permission System** - Includes a permission system for secure tool access
- **Prompt Manipulation** - Provides prompt manipulation capabilities
- **Generation** - Supports text generation from LLM models
- **Sample Tools** - Includes working tools: ReadFile, EditFile, RunTerminalCommand
- **Embeddable Widget** - Reusable chat widget (`ChatWidget`) that can be embedded in applications
- **Current Status** - Builds two shared libraries with headers, VAPI, and GIR files. Includes test executables (`test-ollama` and `test-window`)

## Demo

<video src="https://private-user-images.githubusercontent.com/415282/517941034-0182399e-5418-4dd7-a03e-f6cdc34c7f23.mp4?jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3NjM5NTcwMTksIm5iZiI6MTc2Mzk1NjcxOSwicGF0aCI6Ii80MTUyODIvNTE3OTQxMDM0LTAxODIzOTllLTU0MTgtNGRkNy1hMDNlLWY2Y2RjMzRjN2YyMy5tcDQ_WC1BbXotQWxnb3JpdGhtPUFXUzQtSE1BQy1TSEEyNTYmWC1BbXotQ3JlZGVudGlhbD1BS0lBVkNPRFlMU0E1M1BRSzRaQSUyRjIwMjUxMTI0JTJGdXMtZWFzdC0xJTJGczMlMkZhd3M0X3JlcXVlc3QmWC1BbXotRGF0ZT0yMDI1MTEyNFQwMzU4MzlaJlgtQW16LUV4cGlyZXM9MzAwJlgtQW16LVNpZ25hdHVyZT03OTU1YjNlMzcyNDg3MDQ1YmZhNjIzNjNlNzY0ZmEzNjViOGU0YTMwNDI1ZjI1YzYzNGQwOGQzZmMwMTVmMTk0JlgtQW16LVNpZ25lZEhlYWRlcnM9aG9zdCJ9.iz1emltCz5popYA1xYMVceSQeBQTciSBlvhx9mT-wdM" controls width="100%"></video>

**Note:** If the video doesn't display above, you can [watch it directly here](https://private-user-images.githubusercontent.com/415282/517941034-0182399e-5418-4dd7-a03e-f6cdc34c7f23.mp4?jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3NjM5NTcwMTksIm5iZiI6MTc2Mzk1NjcxOSwicGF0aCI6Ii80MTUyODIvNTE3OTQxMDM0LTAxODIzOTllLTU0MTgtNGRkNy1hMDNlLWY2Y2RjMzRjN2YyMy5tcDQ_WC1BbXotQWxnb3JpdGhtPUFXUzQtSE1BQy1TSEEyNTYmWC1BbXotQ3JlZGVudGlhbD1BS0lBVkNPRFlMU0E1M1BRSzRaQSUyRjIwMjUxMTI0JTJGdXMtZWFzdC0xJTJGczMlMkZhd3M0X3JlcXVlc3QmWC1BbXotRGF0ZT0yMDI1MTEyNFQwMzU4MzlaJlgtQW16LUV4cGlyZXM9MzAwJlgtQW16LVNpZ25hdHVyZT03OTU1YjNlMzcyNDg3MDQ1YmZhNjIzNjNlNzY0ZmEzNjViOGU0YTMwNDI1ZjI1YzYzNGQwOGQzZmMwMTVmMTk0JlgtQW16LVNpZ25lZEhlYWRlcnM9aG9zdCJ9.iz1emltCz5popYA1xYMVceSQeBQTciSBlvhx9mT-wdM).

## Documentation

Online API documentation is available:

- **[ollmchat API Reference](https://roojs.github.io/OLLMchat/ollmchat/ollmchat/index.htm)** - Base library documentation
- **[ollmchat-ui API Reference](https://roojs.github.io/OLLMchat/ollmchat-ui/ollmchat-ui/index.htm)** - UI library documentation

## Build Instructions

This directory contains the OLLMchat library and test applications for working with Ollama API and prompt generation.

## Building

To build the project, follow these steps:

### 1. Setup the build directory

From the `src/OLLMchat` directory, run:

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
- `libollmchat.so` - Base library (with headers, VAPI, and GIR files)
- `libollmchat-ui.so` - UI library (with headers, VAPI, and GIR files)
- `test-ollama` - Command-line test executable
- `test-window` - GTK UI test executable
- Valadoc documentation (in `docs/ollmchat/` and `docs/ollmchat-ui/`)

## Project Structure

- `Ollama/` - Ollama API client implementation
- `Prompt/` - Prompt generation system for different agent types
- `ChatPermission/` - Permission system for tool access control
- `Tools/` - Tool implementations (ReadFile, EditFile, RunTerminalCommand, etc.)
- `UI/` - GTK UI components for chat interface
- `resources/` - Resource files including prompt templates
- `docs/` - Generated documentation (Valadoc) and implementation plans

## Dependencies

**Base library (`libollmchat.so`)**:
- Gee
- GLib/GIO
- json-glib
- libsoup-3.0

**UI library (`libollmchat-ui.so`)**:
- All base library dependencies
- GTK4
- gtksourceview-5

**Test executables**:
- All dependencies above (test-window requires gtksourceview-5)

## License

This project is licensed under the GNU Lesser General Public License version 3.0 (LGPL-3.0). See the [LICENSE](LICENSE) file for details.


## Notes

- The build system uses Meson and Ninja
- Resources are compiled into the binary using GLib's resource system
- The prompt system loads agent-specific sections from resource files
- Libraries are built as shared libraries with C headers, VAPI files, and GObject Introspection (GIR) files
- Valadoc documentation is automatically generated in `docs/ollmchat/` and `docs/ollmchat-ui/`

