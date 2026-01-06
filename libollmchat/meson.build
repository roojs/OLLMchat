# Build base library (libollmchat.so) - no GTK dependencies
# Depends on libocsqlite
#
# NOTE: If you add/remove/change source files in this directory, you MUST also
# update docs/meson.build to include the same files in the valadoc input list.

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
# Settings files must come first as they are used by other files
ollmchat_ollama_src = files([
  'ApplicationInterface.vala',
  'Settings/Connection.vala',
  'Settings/ModelUsage.vala',
  'Settings/ConnectionModels.vala',
  'Settings/Config1.vala',
  'Settings/Config2.vala',
  'Settings/BaseToolConfig.vala',
  'Settings/ModelTag.vala',
  'Settings/AvailableModel.vala',
  'Settings/AvailableModels.vala',
  'Prompt/BaseAgent.vala',  # Must come before Client.vala (Client uses Prompt.BaseAgent)
  'Prompt/AgentHandler.vala',  # Must come after BaseAgent (AgentHandler references BaseAgent)
  'Prompt/JustAsk.vala',
  'Call/Base.vala',
  'Call/Version.vala',
  'Client.vala',
  'OllamaBase.vala',
  'Response/Base.vala',
  'Response/CallFunction.vala',
  'Response/Chat.vala',
  'Response/Embed.vala',
  'Response/Model.vala',
  'Response/Pull.vala',
  'Response/ToolCall.vala',
  'Call/Chat.vala',
  'Call/Embed.vala',
  'Call/Models.vala',
  'Call/Options.vala',
  'Call/Ps.vala',
  'Call/Pull.vala',
  'Call/ShowModel.vala',
  'Message.vala',
  'ChatContentInterface.vala',
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


# Build rpath for libraries to find each other in build directory
lib_build_rpath = ':'.join([
  meson.current_build_dir(),
  meson.current_build_dir() / '..' / 'libocsqlite',
  meson.current_build_dir() / '..' / 'libocmarkdown',
  meson.current_build_dir() / '..' / 'libocmarkdowngtk',
  meson.current_build_dir() / '..' / 'libollmchatgtk'
])

ollmchat_base_lib = library('ollmchat',
  dependencies: [ollmchat_deps, ocsqlite_vapi_dep, ocagent_vapi_dep, ocmarkdown_vapi_dep],
  sources: [ollmchat_ollama_src, ollmchat_resources],
  vala_header: 'ollmchat.h',
  vala_vapi: 'ollmchat.vapi',
  # Don't use link_with for ocsqlite_base_lib to prevent determine_dep_vapis() from finding
  # ocsqlite-meson.vapi and adding it as a source. Link manually via ocsqlite_vapi_dep link_args instead.
  build_rpath: lib_build_rpath,
  link_args: ['-lm'],  # Link math library for Math.sqrt() in Embed.vala
  vala_args: ['--pkg=sqlite3', '--pkg=ocsqlite', '--pkg=ocagent', '--pkg=ocmarkdown', '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite', '--vapidir', meson.current_build_dir() / '..' / 'libocagent', '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdown'],
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
  link_with: [ocsqlite_base_lib, ocagent_base_lib],
  dependencies: [dependency('sqlite3')],
  extra_args: [
    '--extra-library=ocsqlite',
    '--extra-library=ocagent',
    '--accept-unprefixed'
  ],
  includes: ['GObject-2.0', 'Gio-2.0', 'Json-1.0', ocsqlite_gir[0], ocagent_gir[0]],
  install: true,
  fatal_warnings: false
)

# Create dependency for other libraries to use
# Note: We need to manually create the VAPI dependency similar to ocsqlite
# For now, we'll use link_args to ensure the library is linked
ollmchat_vapi_dep = declare_dependency(
  link_args: ['-L' + meson.current_build_dir(), '-lollmchat'],
  dependencies: [ocsqlite_vapi_dep]
)
