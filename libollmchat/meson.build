# Build base library (libollmchat.so) - no GTK dependencies
# Depends on libocsqlite

# Dependencies for ollmchat library
valac = meson.get_compiler('vala')
ollmchat_deps = [
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
  '../resources/gresources.xml',
  source_dir: ['../resources/ollmchat-agents', '../resources'],
  c_name: 'ollmchat_resources'
)

# Source files for OLLMchat namespace (needed by CodeAssistant)
ollmchat_ollama_src = files([
  'Client.vala',
  'Call/Base.vala',
  'Call/Chat.vala',
  'Call/Embed.vala',
  'Call/Models.vala',
  'Call/Options.vala',
  'Call/Ps.vala',
  'Call/ShowModel.vala',
  'Message.vala',
  'ChatContentInterface.vala',
  'OllamaBase.vala',
  'Response/Base.vala',
  'Response/CallFunction.vala',
  'Response/Chat.vala',
  'Response/Embed.vala',
  'Response/Model.vala',
  'Response/ToolCall.vala',
  'Tool/RequestBase.vala',
  'Tool/Tool.vala',
  'Tool/Param.vala',
  'Tool/ParamSimple.vala',
  'Tool/ParamObject.vala',
  'Tool/ParamArray.vala',
  'Tool/Function.vala',
  'ChatPermission/Provider.vala',
  'ChatPermission/Dummy.vala',
  'History/Manager.vala',
  'History/SessionBase.vala',
  'History/Session.vala',
  'History/EmptySession.vala',
  'History/SessionJson.vala',
  'History/SessionPlaceholder.vala',
  'History/TitleGenerator.vala',
  'Call/Generate.vala',
  'Response/Generate.vala',
])

# Source files for prompt system
ollmchat_prompt_src = files([
  'Prompt/BaseAgent.vala',
  'Prompt/AgentInterface.vala',
  'Prompt/CodeAssistantDummy.vala',
  'Prompt/CodeAssistant.vala',
])

# Source files for Tools namespace (base, no GTK)
ollmchat_tools_src = files([
  'Tools/ReadFile.vala',
  'Tools/RequestReadFile.vala',
  'Tools/EditMode.vala',
  'Tools/RequestEditMode.vala',
  'Tools/EditModeChange.vala',
  'Tools/RunCommand.vala',
  'Tools/RequestRunCommand.vala',
])

# Build rpath for libraries to find each other in build directory
lib_build_rpath = ':'.join([
  meson.current_build_dir(),
  meson.current_build_dir() / '..' / 'libocsqlite',
  meson.current_build_dir() / '..' / 'libocmarkdown',
  meson.current_build_dir() / '..' / 'libocmarkdowngtk',
  meson.current_build_dir() / '..' / 'libollmchatgtk'
])

ollmchat_base_lib = library('ollmchat',
  dependencies: [ollmchat_deps, ocsqlite_vapi_dep],
  sources: [ollmchat_ollama_src, ollmchat_prompt_src, ollmchat_tools_src, ollmchat_resources],
  vala_header: 'ollmchat.h',
  vala_vapi: 'ollmchat.vapi',
  # Don't use link_with for ocsqlite_base_lib to prevent determine_dep_vapis() from finding
  # ocsqlite-meson.vapi and adding it as a source. Link manually via ocsqlite_vapi_dep link_args instead.
  build_rpath: lib_build_rpath,
  vala_args: ['--pkg=sqlite3', '--pkg=ocsqlite', '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite'],
  install: true
)

# GObject Introspection for base library
# Note: GIR generation may fail if symbols aren't properly exported
# This is optional and can be fixed later if needed
ollmchat_gir = gnome.generate_gir(ollmchat_base_lib,
  namespace: 'OLLMchat',
  nsversion: '1.0',
  identifier_prefix: 'OLLMchat',
  symbol_prefix: 'ollmchat',
  link_with: [ocsqlite_base_lib],
  dependencies: [dependency('sqlite3')],
  extra_args: [
    '--extra-library=ocsqlite',
    '--accept-unprefixed'
  ],
  includes: ['GObject-2.0', 'Gio-2.0', 'Json-1.0', ocsqlite_gir[0]],
  install: true,
  fatal_warnings: false
)
