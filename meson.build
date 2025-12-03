project('ollmchat', 'vala', 'c',
  version: '1.0.0',
  license: 'LGPL',
  default_options: [
    'default_library=shared',
    'c_std=gnu11',
    'prefix=/usr'
  ]
)

gnome = import('gnome')

valac = meson.get_compiler('vala')

add_project_arguments(['--vapidir', meson.current_source_dir() / 'vapi'], language: 'vala')
add_project_arguments(['--vapidir', meson.current_source_dir() / '../vapi'], language: 'vala')
add_project_arguments(['--target-glib=auto'], language: 'vala')

# Base library dependencies (no GTK)
base_deps = [
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('json-glib-1.0'),
  dependency('libsoup-3.0'),
  dependency('libxml-2.0'),
  valac.find_library('posix'),
]

# UI library dependencies (includes GTK)
ui_deps = [
  dependency('gtk4'),
  dependency('gtksourceview-5'),
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('json-glib-1.0'),
  dependency('libsoup-3.0'),
  valac.find_library('posix'),
]

# Dependencies for test-window (includes GTK UI)
test_window_deps = [
  dependency('gtk4'),
  dependency('gtksourceview-5'),
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('json-glib-1.0'),
  dependency('libsoup-3.0'),
  valac.find_library('posix'),
]

# Dependencies for test-ollama (command-line only)
test_ollama_deps = [
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('json-glib-1.0'),
  dependency('libsoup-3.0'),
  valac.find_library('posix'),
]

# Compile resources for prompt system
ollmchat_resources = gnome.compile_resources(
  'ollmchat-resources',
  'resources/gresources.xml',
  source_dir: ['resources/ollmchat-agents', 'resources'],
  c_name: 'ollmchat_resources'
)

# Source files for Ollama namespace (needed by CodeAssistant)
ollmchat_ollama_src = files([
  'Ollama/Client.vala',
  'Ollama/Call/BaseCall.vala',
  'Ollama/Call/ChatCall.vala',
  'Ollama/Call/EmbedCall.vala',
  'Ollama/Call/ModelsCall.vala',
  'Ollama/Call/Options.vala',
  'Ollama/Call/PsCall.vala',
  'Ollama/Call/ShowModelCall.vala',
  'Ollama/Message.vala',
  'Ollama/MessageInterface.vala',
  'Ollama/OllamaBase.vala',
  'Ollama/Response/BaseResponse.vala',
  'Ollama/Response/CallFunction.vala',
  'Ollama/Response/ChatResponse.vala',
  'Ollama/Response/EmbedResponse.vala',
  'Ollama/Response/Model.vala',
  'Ollama/Response/ToolCall.vala',
  'Ollama/Tool/Tool.vala',
  'Ollama/Tool/Param.vala',
  'Ollama/Tool/ParamSimple.vala',
  'Ollama/Tool/ParamObject.vala',
  'Ollama/Tool/ParamArray.vala',
  'Ollama/Tool/Function.vala',
])

# Source files for prompt system
ollmchat_prompt_src = files([
  'Prompt/BaseAgentPrompt.vala',
  'Prompt/CodeAssistantProviderInterface.vala',
  'Prompt/CodeAssistantProviderDummy.vala',
  'Prompt/CodeAssistant.vala',
])

# Source files for ChatPermission namespace (base classes, no GTK)
ollmchat_chatpermission_src = files([
  'ChatPermission/Provider.vala',
  'ChatPermission/Dummy.vala',
])

# Source files for ChatPermission namespace (GTK-dependent)
ollmchat_chatpermission_ui_src = files([
  'ChatPermission/ChatView.vala',
])

# Source files for Tools namespace (base, no GTK)
ollmchat_tools_src = files([
  'Tools/ReadFile.vala',
  'Tools/EditMode.vala',
  'Tools/EditModeChange.vala',
  'Tools/RunCommand.vala',
])


# Source files for Tools namespace (GTK-dependent)
ollmchat_tools_ui_src = files([
  'ToolsUI/RunCommand.vala',
])

# Source files for Markdown namespace (base, no GTK) - for libomarkdown
omarkdown_src = files([
  'Markdown/Parser.vala',
  'Markdown/RenderBase.vala',
  'Markdown/PangoRender.vala',
  'Markdown/DummyRenderer.vala',
  'Markdown/FromHTML.vala',
  'Markdown/Tags.vala',
  'Markdown/TagsTable.vala',
  'Markdown/Writer.vala',
])

# Source files for MarkdownGtk namespace (GTK-dependent) - for libomarkdown-ui
omarkdown_ui_src = files([
  'MarkdownGtk/Render.vala',
  'MarkdownGtk/State.vala',
  'MarkdownGtk/TopState.vala',
  'MarkdownGtk/Table.vala',
  'MarkdownGtk/TableCell.vala',
])

# UI source files (for UI library and test-window)
ollmchat_ui_src = files([
  'UI/ChatWidget.vala',
  'UI/ChatView.vala',
  'UI/ChatInput.vala',
  'UI/ChatPermission.vala',
]) + ollmchat_tools_ui_src

# Build omarkdown base library (libomarkdown.so) - no GTK dependencies
omarkdown_base_lib = library('omarkdown',
  dependencies: base_deps,
  sources: [omarkdown_src],
  vala_header: 'omarkdown.h',
  vala_vapi: 'omarkdown.vapi',
  install: true
)

# Build omarkdown UI library (libomarkdown-ui.so) - depends on omarkdown base library
omarkdown_ui_lib = library('omarkdown-ui',
  dependencies: ui_deps,
  sources: [omarkdown_ui_src],
  vala_header: 'omarkdown-ui.h',
  vala_vapi: 'omarkdown-ui.vapi',
  link_with: [omarkdown_base_lib],
  vala_args: ['--vapidir', meson.current_build_dir(), '--pkg=omarkdown'],  # Add build dir and pkg to find omarkdown.vapi
  install: true
)

# Build base library (libollmchat.so) - no GTK dependencies
ollmchat_base_lib = library('ollmchat',
  dependencies: base_deps,
  sources: [ollmchat_ollama_src, ollmchat_prompt_src, ollmchat_chatpermission_src, ollmchat_tools_src, ollmchat_resources],
  vala_header: 'ollmchat.h',
  vala_vapi: 'ollmchat.vapi',
  link_with: [omarkdown_base_lib],
  install: true
)

# Build UI library (libollmchat-ui.so) - depends on base library and omarkdown-ui
ollmchat_ui_lib = library('ollmchat-ui',
  dependencies: ui_deps,
  sources: [ollmchat_chatpermission_ui_src, ollmchat_tools_ui_src, ollmchat_ui_src],
  vala_header: 'ollmchat-ui.h',
  vala_vapi: 'ollmchat-ui.vapi',
  link_with: [ollmchat_base_lib, omarkdown_ui_lib],
  install: true
)

# GObject Introspection for omarkdown base library
# Note: Symbol prefix matches the namespace (OLLMchat.Markdown)
omarkdown_gir = gnome.generate_gir(omarkdown_base_lib,
  namespace: 'OMarkdown',
  nsversion: '1.0',
  identifier_prefix: 'OLLMchat',
  symbol_prefix: 'oll_mchat',
  includes: ['GObject-2.0', 'Gio-2.0'],
  install: true,
  fatal_warnings: false
)

# GObject Introspection for omarkdown UI library
# Note: Symbol prefix matches the namespace (OLLMchat.MarkdownGtk)
omarkdown_ui_header_file = meson.current_build_dir() / 'omarkdown-ui.h'
omarkdown_ui_gir = gnome.generate_gir(omarkdown_ui_lib,
  namespace: 'OMarkdownUI',
  nsversion: '1.0',
  identifier_prefix: 'OLLMchat',
  symbol_prefix: 'oll_mchat',
  sources: [omarkdown_ui_header_file],
  link_with: [omarkdown_base_lib],
  extra_args: [
    '--extra-library=omarkdown',
    '--accept-unprefixed'
  ],
  includes: ['GObject-2.0', 'Gio-2.0', 'Gtk-4.0', 'Gee-0.8', omarkdown_gir[0]],
  install: true,
  fatal_warnings: false
)

# GObject Introspection for base library
# Note: GIR generation may fail if symbols aren't properly exported
# This is optional and can be fixed later if needed
ollmchat_gir = gnome.generate_gir(ollmchat_base_lib,
  namespace: 'OLLMchat',
  nsversion: '1.0',
  identifier_prefix: 'OLLMchat',
  symbol_prefix: 'ollmchat',
  includes: ['GObject-2.0', 'Gio-2.0', 'Json-1.0'],
  install: true,
  fatal_warnings: false
)

# GObject Introspection for UI library
# Identifier prefix is 'OLLMchat' because the UI library contains symbols from
# multiple namespaces (OLLMchat.ChatPermission, OLLMchat.ToolsUI, OLLMchat.UI)
# that all start with 'OLLMchat'
# We include the base library GIR so the UI library can reference base types
# For Vala libraries, meson doesn't automatically populate the filelist with the header.
# We need to pass the header file explicitly in the 'sources' parameter.
# The header file is generated in the build directory by the Vala compiler.
ollmchat_ui_header_file = meson.current_build_dir() / 'ollmchat-ui.h'
ollmchat_ui_gir = gnome.generate_gir(ollmchat_ui_lib,
  namespace: 'OLLMchatUI',
  nsversion: '1.0',
  identifier_prefix: 'OLLMchat',
  symbol_prefix: 'ollmchat',
  sources: [ollmchat_ui_header_file],
  link_with: [ollmchat_base_lib],
  extra_args: [
    '--extra-library=ollmchat',
    '--accept-unprefixed'
  ],
  includes: ['GObject-2.0', 'Gio-2.0', 'Gtk-4.0', 'GtkSource-5', 'Gee-0.8', ollmchat_gir[0]],
  install: true,
  fatal_warnings: false
)

# Generate Valadoc documentation (single unified documentation)
# valadoc is required - meson will fail during configuration if it's not found
valadoc = find_program('valadoc', required: true)

# Combined documentation for both base and UI libraries
valadoc_dir = meson.current_source_dir() / 'docs' / 'ollmchat'
valadoc_clean = custom_target('valadoc-clean',
  output: 'valadoc-clean',
  command: [find_program('rm'), '-rf', valadoc_dir],
  build_by_default: false
)
valadoc_docs = custom_target('valadoc',
  input: ollmchat_ollama_src + ollmchat_prompt_src + ollmchat_chatpermission_src + ollmchat_tools_src + ollmchat_chatpermission_ui_src + ollmchat_ui_src + omarkdown_src + omarkdown_ui_src,
  output: ['valadoc'],
  depends: [valadoc_clean],
  command: [
    valadoc,
    '--package-name=ollmchat',
    '--package-version=@0@'.format(meson.project_version()),
    '--vapidir', meson.current_source_dir() / '../vapi',
    '--vapidir', meson.current_source_dir() / 'vapi',
    '--pkg=gee-0.8',
    '--pkg=gio-2.0',
    '--pkg=glib-2.0',
    '--pkg=gobject-2.0',
    '--pkg=json-glib-1.0',
    '--pkg=libsoup-3.0',
    '--pkg=libxml-2.0',
    '--pkg=gtk4',
    '--pkg=gtksourceview-5',
    '--pkg=posix',
    '--doclet=html',
    '--directory=' + valadoc_dir,
    '@INPUT@'
  ],
  build_by_default: true,
  install: false
)

# Build test-ollama executable (command-line test)
test_ollama = executable('test-ollama',
  dependencies: test_ollama_deps,
  sources: ['TestOllama.vala'],
  link_with: [ollmchat_base_lib],
  install: false
)

# Build test-window executable (GTK UI test)
# Include resources directly in the executable to ensure they're registered
test_window = executable('test-window',
  dependencies: test_window_deps,
  sources: ['TestWindow.vala', ollmchat_resources],
  link_with: [ollmchat_base_lib, ollmchat_ui_lib, omarkdown_ui_lib],
  install: false
)


# Build test-markdown-parser executable (Markdown parser test with dummy renderer)
test_markdown_parser = executable('test-markdown-parser',
  dependencies: test_window_deps,
  sources: ['test-markdown-parser.vala'],
  link_with: [omarkdown_base_lib, omarkdown_ui_lib],
  install: false
)

