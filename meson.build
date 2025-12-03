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
valac_exe = find_program('valac')

add_project_arguments(['--vapidir', meson.current_source_dir() / 'vapi'], language: 'vala')
add_project_arguments(['--vapidir', meson.current_source_dir() / '../vapi'], language: 'vala')
add_project_arguments(['--vapidir', meson.current_build_dir()], language: 'vala')  # Add build dir for generated VAPIs
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

# Source files for OLLMchat namespace (needed by CodeAssistant)
ollmchat_ollama_src = files([
  'OLLMchat/Client.vala',
  'OLLMchat/Call/Base.vala',
  'OLLMchat/Call/Chat.vala',
  'OLLMchat/Call/Embed.vala',
  'OLLMchat/Call/Models.vala',
  'OLLMchat/Call/Options.vala',
  'OLLMchat/Call/Ps.vala',
  'OLLMchat/Call/ShowModel.vala',
  'OLLMchat/Message.vala',
  'OLLMchat/MessageInterface.vala',
  'OLLMchat/OllamaBase.vala',
  'OLLMchat/Response/Base.vala',
  'OLLMchat/Response/CallFunction.vala',
  'OLLMchat/Response/Chat.vala',
  'OLLMchat/Response/Embed.vala',
  'OLLMchat/Response/Model.vala',
  'OLLMchat/Response/ToolCall.vala',
  'OLLMchat/Tool/Tool.vala',
  'OLLMchat/Tool/Param.vala',
  'OLLMchat/Tool/ParamSimple.vala',
  'OLLMchat/Tool/ParamObject.vala',
  'OLLMchat/Tool/ParamArray.vala',
  'OLLMchat/Tool/Function.vala',
  'OLLMchat/ChatPermission/Provider.vala',
  'OLLMchat/ChatPermission/Dummy.vala',
  'OLLMchat/History/Manager.vala',
  'OLLMchat/History/Session.vala',
])

# Source files for prompt system - moved to OLLMchat/Prompt/
ollmchat_prompt_src = files([
  'OLLMchat/Prompt/BaseAgent.vala',
  'OLLMchat/Prompt/AgentInterface.vala',
  'OLLMchat/Prompt/CodeAssistantDummy.vala',
  'OLLMchat/Prompt/CodeAssistant.vala',
])

# Source files for ChatPermission namespace (moved to Ollama.ChatPermission)
# Provider and Dummy are now in OLLMchat/ChatPermission/
# Permission (formerly ChatView) is now in OLLMchatGtk.Tools/

# Source files for Tools namespace (base, no GTK) - moved to OLLMchat.Tools
ollmchat_tools_src = files([
  'OLLMchat/Tools/ReadFile.vala',
  'OLLMchat/Tools/EditMode.vala',
  'OLLMchat/Tools/EditModeChange.vala',
  'OLLMchat/Tools/RunCommand.vala',
])


# Source files for Tools namespace (GTK-dependent) - moved to OLLMchatGtk.Tools
ollmchat_tools_ui_src = files([
  'OLLMchatGtk/Tools/RunCommand.vala',
  'OLLMchatGtk/Tools/Permission.vala',
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

# UI source files (for UI library and test-window) - renamed to OLLMchatGtk
ollmchat_ui_src = files([
  'OLLMchatGtk/ChatWidget.vala',
  'OLLMchatGtk/ChatView.vala',
  'OLLMchatGtk/ChatInput.vala',
  'OLLMchatGtk/ChatPermission.vala',
]) + ollmchat_tools_ui_src

# Build omarkdown base library (libomarkdown.so) - no GTK dependencies
# We'll generate VAPI manually via custom_target to control command line order
# Meson will generate a VAPI with default name 'omarkdown.vapi', but we override it
# by generating our own via custom_target. The meson-generated one won't be used.
omarkdown_base_lib = library('omarkdown',
  dependencies: base_deps,
  sources: [omarkdown_src],
  vala_header: 'omarkdown.h',
  vala_vapi: 'omarkdown-meson.vapi',  # Use different name so our custom_target can use 'omarkdown.vapi'
  install: true
)

# Manually generate omarkdown.vapi with correct command line order
# This replicates the Makefile approach and bypasses meson's determine_dep_vapis()
# Note: We only generate the VAPI file here - the header is generated by omarkdown_base_lib
omarkdown_vapi = custom_target('omarkdown-vapi',
  output: 'omarkdown.vapi',
  input: omarkdown_src,
  command: [
    valac_exe,
    '-C', '--debug',
    '--target-glib=auto',
    '--vapidir', meson.current_source_dir() / 'vapi',
    '--vapidir', meson.current_source_dir() / '../vapi',
    '--vapidir', meson.current_build_dir(),
    '--pkg', 'posix',
    '--pkg', 'libxml-2.0',
    '--pkg', 'libsoup-3.0',
    '--pkg', 'json-glib-1.0',
    '--pkg', 'gobject-2.0',
    '--pkg', 'glib-2.0',
    '--pkg', 'gio-2.0',
    '--pkg', 'gee-0.8',
    '--library', 'omarkdown',
    '--header', meson.current_build_dir() / 'omarkdown.h',  # Use header from library
    '--vapi', '@OUTPUT@',
    '@INPUT@'
  ],
  depends: [omarkdown_base_lib],  # Ensure library is built first (so header exists)
  build_by_default: true
)

# Build omarkdown UI library (libomarkdown-ui.so) - depends on omarkdown base library
# We'll generate VAPI manually via custom_target to control command line order
# Meson will generate a VAPI with default name 'omarkdown-ui.vapi', but we override it
# by generating our own via custom_target. The meson-generated one won't be used.
omarkdown_ui_lib = library('omarkdown-ui',
  dependencies: ui_deps,
  sources: [omarkdown_ui_src],
  vala_header: 'omarkdown-ui.h',
  vala_vapi: 'omarkdown-ui-meson.vapi',  # Use different name so our custom_target can use 'omarkdown-ui.vapi'
  link_with: [omarkdown_base_lib],
  install: true
)

# Manually generate omarkdown-ui.vapi with correct command line order
# --vapidir and --pkg flags come before source files, ensuring packages load first
# Note: We only generate the VAPI file here - the header is generated by omarkdown_ui_lib
omarkdown_ui_vapi = custom_target('omarkdown-ui-vapi',
  output: 'omarkdown-ui.vapi',
  input: omarkdown_ui_src,
  depends: [omarkdown_vapi, omarkdown_ui_lib],  # Ensure dependencies are built
  command: [
    valac_exe,
    '-C', '--debug',
    '--target-glib=auto',
    '--vapidir', meson.current_source_dir() / 'vapi',
    '--vapidir', meson.current_source_dir() / '../vapi',
    '--vapidir', meson.current_build_dir(),
    '--pkg', 'posix',
    '--pkg', 'libxml-2.0',
    '--pkg', 'libsoup-3.0',
    '--pkg', 'json-glib-1.0',
    '--pkg', 'gobject-2.0',
    '--pkg', 'glib-2.0',
    '--pkg', 'gio-2.0',
    '--pkg', 'gee-0.8',
    '--pkg', 'gtksourceview-5',
    '--pkg', 'gtk4',
    '--pkg', 'omarkdown',  # Package flag comes before source files
    '--library', 'omarkdown-ui',
    '--header', meson.current_build_dir() / 'omarkdown-ui.h',  # Use header from library
    '--vapi', '@OUTPUT@',
    '@INPUT@'
  ],
  build_by_default: true
)

# Build base library (libollmchat.so) - no GTK dependencies
# Don't use link_with for omarkdown_base_lib to prevent determine_dep_vapis() from finding
# omarkdown-meson.vapi and adding it as a source. Link manually instead.
# Create a dependency that includes the VAPI file to ensure build order
# Note: We can't include the library in sources, so we rely on link_args to ensure it's built
omarkdown_vapi_dep = declare_dependency(
  link_args: ['-L' + meson.current_build_dir(), '-lomarkdown'],
  sources: [omarkdown_vapi[0]]  # Include VAPI file to ensure it's built first
)
# omarkdown_vapi_dep is used by the UI library (ollmchat_ui_lib), not the base library
# Ensure omarkdown_base_lib is built before omarkdown_vapi_dep is used
# (meson will detect -lomarkdown in link_args and build the library)

ollmchat_base_lib = library('ollmchat',
  dependencies: base_deps,
  sources: [ollmchat_ollama_src, ollmchat_prompt_src, ollmchat_tools_src, ollmchat_resources],
  vala_header: 'ollmchat.h',
  vala_vapi: 'ollmchat.vapi',
  install: true
)

# Build UI library (libollmchat-ui.so) - depends on base library and omarkdown libraries
# Don't use link_with for omarkdown_ui_lib to prevent determine_dep_vapis() from finding
# omarkdown-ui-meson.vapi and adding it as a source. Link manually instead.
# Create a dependency that includes the VAPI files to ensure build order
omarkdown_ui_vapi_dep = declare_dependency(
  link_args: ['-L' + meson.current_build_dir(), '-lomarkdown-ui'],
  sources: [omarkdown_ui_vapi[0]]  # Include VAPI file to ensure it's built first
)
# Ensure omarkdown_ui_lib is built before omarkdown_ui_vapi_dep is used
# (meson will detect -lomarkdown-ui in link_args and build the library)

ollmchat_ui_lib = library('ollmchat-ui',
  dependencies: [ui_deps, omarkdown_vapi_dep, omarkdown_ui_vapi_dep],
  sources: [ollmchat_tools_ui_src, ollmchat_ui_src],
  vala_header: 'ollmchat-ui.h',
  vala_vapi: 'ollmchat-ui.vapi',
  link_with: [ollmchat_base_lib],  # Link with base library
  # Use --pkg for VAPI access (uses manually generated VAPI files, not meson-generated ones)
  # The omarkdown_vapi_dep and omarkdown_ui_vapi_dep provide link_args for libraries
  # but since we're using declare_dependency with sources (not link_with), determine_dep_vapis() won't find the meson-generated VAPI
  vala_args: ['--pkg=omarkdown', '--pkg=omarkdown-ui', '--vapidir', meson.current_build_dir()],
  install: true
)

# GObject Introspection for omarkdown base library
# Note: Namespace is now Markdown (not OLLMchat.Markdown)
omarkdown_gir = gnome.generate_gir(omarkdown_base_lib,
  namespace: 'OMarkdown',
  nsversion: '1.0',
  identifier_prefix: 'Markdown',
  symbol_prefix: 'markdown',
  includes: ['GObject-2.0', 'Gio-2.0'],
  install: true,
  fatal_warnings: false
)

# GObject Introspection for omarkdown UI library
# Note: Namespace is now MarkdownGtk (not OLLMchat.MarkdownGtk)
omarkdown_ui_header_file = meson.current_build_dir() / 'omarkdown-ui.h'
omarkdown_ui_gir = gnome.generate_gir(omarkdown_ui_lib,
  namespace: 'OMarkdownUI',
  nsversion: '1.0',
  identifier_prefix: 'MarkdownGtk',
  symbol_prefix: 'markdown_gtk',
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
# multiple namespaces (OLLMchatGtk, OLLMchatGtk.Tools) that all start with 'OLLMchat'
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
  input: ollmchat_ollama_src + ollmchat_prompt_src + ollmchat_tools_src + ollmchat_ui_src + omarkdown_src + omarkdown_ui_src,
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
    # Don't use --pkg=omarkdown or --pkg=omarkdown-ui here - valadoc processes source files directly,
    # so it doesn't need VAPI files. Using --pkg would cause duplicate definition errors.
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
# Use omarkdown_ui_vapi_dep which provides link_with but with sources to prevent VAPI being added
test_window = executable('test-window',
  dependencies: [test_window_deps, omarkdown_ui_vapi_dep],
  sources: ['TestWindow.vala', ollmchat_resources],
  link_with: [ollmchat_base_lib, ollmchat_ui_lib],
  # Use --pkg for VAPI access (uses manually generated VAPI files)
  vala_args: ['--pkg=omarkdown', '--pkg=omarkdown-ui', '--vapidir', meson.current_build_dir()],
  install: false
)


# Build test-markdown-parser executable (Markdown parser test with dummy renderer)
test_markdown_parser = executable('test-markdown-parser',
  dependencies: test_window_deps,
  sources: ['test-markdown-parser.vala'],
  link_with: [omarkdown_base_lib, omarkdown_ui_lib],
  install: false
)

