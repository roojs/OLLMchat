# Build base library (libollmchat.so) - no GTK dependencies
# Depends on libocsqlite
#
# NOTE: If you add/remove/change source files in this directory, you MUST also
# update docs/meson.build to include the same files in the valadoc input list.

# Dependencies for ollmchat library
valac = meson.get_compiler('vala')
cc = meson.get_compiler('c')
is_android_cross = host_machine.system() == 'android'
ollmchat_vala_gir = 'OLLMchat-1.0.gir'

ollmchat_deps = [
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('json-glib-1.0'),
  dependency('libsoup-3.0'),
  valac.find_library('posix'),
  ollamaweb_vapi_dep,
]

resource_dirs = [
  '../resources/ollmchat-agents/code-assistant',
  '../resources',
  '../resources/wrapped-tools',
  '../resources/ocvector',
  '../resources/skill-prompts',
  '../resources/skills',
  '../resources/chat-prompts',
  '../resources/pi-prompts',
  '../resources/pi-skills',
  '../resources/tools'
]

resource_source_args = []
foreach resource_dir : resource_dirs
  resource_source_args += ['--sourcedir', meson.current_source_dir() / resource_dir]
endforeach

# Compile resources for prompt system. Use the build-machine tool explicitly so
# cross builds do not try to execute a target-architecture glib-compile-resources.
glib_compile_resources = find_program('glib-compile-resources', native: true)
ollmchat_resources_c = custom_target(
  'ollmchat-resources_c',
  input: '../resources/gresources.xml',
  output: 'ollmchat-resources.c',
  command: [
    glib_compile_resources,
    '@INPUT@',
    resource_source_args,
    '--c-name', 'ollmchat_resources',
    '--internal',
    '--generate-source',
    '--target', '@OUTPUT@',
    '--dependency-file', '@DEPFILE@'
  ],
  depfile: 'ollmchat-resources.c.d'
)

ollmchat_resources_h = custom_target(
  'ollmchat-resources_h',
  input: '../resources/gresources.xml',
  output: 'ollmchat-resources.h',
  command: [
    glib_compile_resources,
    '@INPUT@',
    resource_source_args,
    '--c-name', 'ollmchat_resources',
    '--internal',
    '--generate-header',
    '--target', '@OUTPUT@'
  ]
)
ollmchat_resources = [ollmchat_resources_c, ollmchat_resources_h]

# Source files for OLLMchat namespace (needed by CodeAssistant)
# Settings files must come first as they are used by other files
version_vala = configure_file(
  input: 'version.vala.in',
  output: 'version.vala',
  configuration: { 'VERSION': meson.project_version() }
)
ollmchat_ollama_src = [version_vala] + files([
  'ApplicationInterface.vala',
  'ChatDesktopInterface.vala',
  'Settings/Connection.vala',
  'Settings/SearchFault.vala',
  'Settings/ModelUsage.vala',
  'Settings/ConnectionModels.vala',
  'Settings/Window.vala',  # Before Config2 (Config2.windows uses Window)
  'Settings/Filesd.vala',  # Before Config2 (Config2.filesd)
  'Settings/FilesdClient.vala',  # Before Config2 (Config2.filesd_client)
  'Settings/Config2.vala',
  'Settings/BaseToolConfig.vala',
  'Settings/AgentConfig.vala',
  'Settings/RequiresModelsInterface.vala',
  'Settings/SearchResults.vala',
  'OllmError.vala',  # Must come early - used by many files
  'Agent/Factory.vala',  # Must come before Client.vala (Client uses Agent.Factory)
  'Agent/Interface.vala',  # Must come before Base (Base implements Interface)
  'Agent/Base.vala',  # Must come after Factory (Base references Factory)
  'Agent/Summarizer.vala',  # Must come after Agent/Base and Agent/Factory
  'Agent/JustAskFactory.vala',  # Must come after Base (JustAskFactory uses Factory)
  'Agent/JustAsk.vala',  # Must come after JustAskFactory (JustAsk uses Base)
  'Chatter/namespace.vala',
  'Chatter/Factory.vala',  # Must come after Agent/Factory
  'Chatter/PendingMessage.vala',  # Must come before Chatter/Agent
  'Chatter/Agent.vala',  # Must come after Agent/Base and Chatter/Factory
  'Call/Base.vala',
  'Call/ChatBase.vala',
  'Call/Version.vala',
  'Client.vala',
  'Response/Base.vala',
  'Response/CallFunction.vala',
  'Response/Chunk.vala',
  'Response/Chat.vala',
  'Response/FloatArray.vala',
  'Response/Embed.vala',
  'Response/Model.vala',
  'Response/Pull.vala',
  'Response/Create.vala',
  'Response/ToolCall.vala',
  'Response/Usage.vala',
  'Response/EmbeddingDatum.vala',
  'Response/EmbeddingList.vala',
  'Call/Chat.vala',
  'Call/ReplayChat.vala',
  'Call/Embed.vala',
  'Call/Models.vala',
  'Call/ChatCompletions.vala',
  'Call/Embeddings.vala',
  'Call/Completions.vala',
  'Call/Tags.vala',
  'Call/Options.vala',
  'Call/Ps.vala',
  'Call/Pull.vala',
  'Call/Create.vala',
  'Call/Delete.vala',
  'Call/ShowModel.vala',
  'Message.vala',
  'MessageQueue.vala',
  'ChatContentInterface.vala',
  'Tool/RequestBase.vala',
  'Tool/BaseTool.vala',
  'Tool/WrapInterface.vala',
  'Tool/UiWidgets.vala',
  'Tool/ParamParser.vala',
  'Tool/Param.vala',
  'Tool/ParamSimple.vala',
  'Tool/ParamObject.vala',
  'Tool/ParamArray.vala',
  'Tool/Function.vala',
  'ChatPermission/Provider.vala',
  'ChatPermission/Dummy.vala',
  'History/Manager.vala',
  'History/SessionList.vala',
  'History/SessionBase.vala',
  'History/Session.vala',
  'History/EmptySession.vala',
  'History/SessionJson.vala',
  'History/SessionPlaceholder.vala',
  'History/TitleGenerator.vala',
  'Call/Generate.vala',
  'Response/Generate.vala',
  'Prompt/Template.vala',
])

# Build rpath for libraries to find each other in build directory
lib_build_rpath = ':'.join([
  meson.current_build_dir(),
  meson.current_build_dir() / '..' / 'libocsqlite',
  meson.current_build_dir() / '..' / 'libocrpc',
  meson.current_build_dir() / '..' / 'libocmarkdown',
  meson.current_build_dir() / '..' / 'libocmarkdowngtk',
  meson.current_build_dir() / '..' / 'libollmchatgtk',
  meson.current_build_dir() / '..' / 'libollamaweb'
])

if is_android_cross
  ollmchat_base_lib = library('ollmchat',
    dependencies: [ollmchat_deps, ocsqlite_vapi_dep, ocmarkdown_vapi_dep, ocrpc_vapi_dep],
    sources: [ollmchat_ollama_src, ollmchat_resources],
    vala_header: 'ollmchat.h',
    vala_vapi: 'ollmchat.vapi',
    build_rpath: lib_build_rpath,
    link_args: ['-lm'],  # Link math library for Math.sqrt() in Embed.vala
    vala_args: [
      '--pkg=sqlite3', '--pkg=ocsqlite', '--pkg=ocmarkdown', '--pkg=ollamaweb',
      '--pkg=ocrpc',
      '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
      '--vapidir', meson.current_build_dir() / '..' / 'libocrpc',
      '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdown',
      '--vapidir', meson.current_build_dir() / '..' / 'libollamaweb',
      '--girdir', meson.current_build_dir() / '..' / 'libocsqlite',
      '--girdir', meson.current_build_dir() / '..' / 'libocmarkdown',
    ],
    install: true
  )
else
  ollmchat_base_lib = library('ollmchat',
    dependencies: [ollmchat_deps, ocsqlite_vapi_dep, ocmarkdown_vapi_dep, ocrpc_vapi_dep],
    sources: [ollmchat_ollama_src, ollmchat_resources],
    vala_header: 'ollmchat.h',
    vala_vapi: 'ollmchat.vapi',
    vala_gir: ollmchat_vala_gir,
    # Don't use link_with for ocsqlite_base_lib to prevent determine_dep_vapis() from finding
    # ocsqlite-meson.vapi and adding it as a source. Link manually via ocsqlite_vapi_dep link_args instead.
    build_rpath: lib_build_rpath,
    link_args: ['-lm'],  # Link math library for Math.sqrt() in Embed.vala
    vala_args: [
      '--pkg=sqlite3', '--pkg=ocsqlite', '--pkg=ocmarkdown', '--pkg=ollamaweb',
      '--pkg=ocrpc',
      '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
      '--vapidir', meson.current_build_dir() / '..' / 'libocrpc',
      '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdown',
      '--vapidir', meson.current_build_dir() / '..' / 'libollamaweb',
      '--girdir', meson.current_build_dir() / '..' / 'libocsqlite',
      '--girdir', meson.current_build_dir() / '..' / 'libocmarkdown',
    ],
    install: true
  )
endif

ollmchat_gir_file = meson.current_build_dir() / 'OLLMchat-1.0.gir'
if g_ir_compiler.found()
  custom_target('ollmchat-typelib',
    output: 'OLLMchat-1.0.typelib',
    command: [
      g_ir_compiler, ollmchat_gir_file, '--output', '@OUTPUT@',
      '--includedir', meson.current_build_dir() / '..' / 'libocsqlite',
      '--includedir', meson.current_build_dir() / '..' / 'libocmarkdown',
      '--includedir', '/usr/share/gir-1.0',
    ],
    depends: ollmchat_base_lib,
    build_by_default: true,
    install: true,
    install_dir: get_option('libdir') / 'girepository-1.0',
  )
  meson.add_install_script(
    'sh', '-c',
    'install -Dm644 "' + ollmchat_gir_file + '" "$DESTDIR$MESON_INSTALL_PREFIX/share/gir-1.0/OLLMchat-1.0.gir"',
  )
endif
meson.add_install_script(
  'sh', '-c',
  'install -Dm644 "' + meson.current_build_dir() / 'ollmchat.vapi' + '" "$DESTDIR$MESON_INSTALL_PREFIX/share/vala/vapi/ollmchat.vapi"',
)

# link_with is what puts ollmchat.vapi on the consumer's valac inputs.
# link_args alone only order the later link step, so liboccoder can run
# valac before this library has written ollmchat.vapi.
ollmchat_vapi_dep = declare_dependency(
  link_with: ollmchat_base_lib,
  link_args: [
    '-L' + meson.current_build_dir() / '..' / 'libollamaweb', '-lollamaweb',
  ],
  dependencies: [ocsqlite_vapi_dep, ollamaweb_vapi_dep, ocrpc_vapi_dep, ocmarkdown_vapi_dep]
)
