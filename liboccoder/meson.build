# Build occoder library (liboccoder.so) - depends on libocsqlite, libocfiles

# Dependencies for occoder library
valac = meson.get_compiler('vala')
occoder_deps = [
  dependency('gtk4'),
  dependency('libadwaita-1'),
  dependency('gtksourceview-5'),
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('json-glib-1.0'),
  dependency('libsoup-3.0'),  # Required for ollmchat (Soup.Message, Soup.Session)
  dependency('sqlite3'),
  dependency('libgit2-glib-1.0'),
  valac.find_library('posix'),
]

occoder_src = files([
  'BufferProvider.vala',
  # TODO: Clipboard feature needs proper design - see TODO.md
  # 'ClipboardMetadata.vala',
  'GitProvider.vala',
  'GtkSourceFileBuffer.vala',  # Must come before SourceView.vala (SourceView uses GtkSourceFileBuffer)
  'SearchableDropdown.vala',
  'ProjectDropdown.vala',
  'FileDropdown.vala',
  'SourceView.vala',
  'AgentFactory.vala',  # Must come after SourceView (AgentFactory uses SourceView)
  'Agent.vala',  # Must come after AgentFactory (Agent uses AgentFactory)
  'Skill/PromptTemplate.vala',
  'Skill/Definition.vala',
  'Skill/Manager.vala',
  'Skill/Factory.vala',
  'Task/PhaseEnum.vala',  # Task: PhaseEnum (no other Task deps)
  'Task/ProgressItem.vala',
  'Task/ProgressRunner.vala',
  'Task/Step.vala',     # Task: Step → Details
  'Task/Details.vala',  # Task: Details → ResultParser, Tool
  'Task/ValidateLink.vala',  # after Details (uses Details; Details delegates link validation)
  'Task/ResolveLink.vala',
  'Task/Tool.vala',     # Task: Tool → Details
  'Task/ToolList.vala',
  'Task/WriteChange.vala',  # after Tool.vala
  'Task/List.vala',     # Task: List → Step, Details
  'Task/ProgressList.vala',
  'Task/ProgressView.vala',
  'Skill/Runner.vala',  # after Task/ProgressList (Runner.progress)
  'Task/ResultParser.vala',  # Task: ResultParser → List, Step, Details, Tool
  'List/SortedList.vala',  # Must come before Approvals (Approvals uses SortedList)
  'Approvals.vala',
])

# Build rpath for libraries to find each other in build directory
lib_build_rpath = ':'.join([
  meson.current_build_dir(),
  meson.current_build_dir() / '..' / 'libocsqlite',
  meson.current_build_dir() / '..' / 'libocfiles',
  meson.current_build_dir() / '..' / 'libocmarkdown',
  meson.current_build_dir() / '..' / 'libocmarkdowngtk',
  meson.current_build_dir() / '..' / 'libollmchat',
  meson.current_build_dir() / '..' / 'libollmchatgtk',
  meson.current_build_dir() / '..' / 'libocvector',
  meson.current_build_dir() / '..' / 'liboctools'
])

occoder_base_lib = library('occoder',
  dependencies: [occoder_deps, ocsqlite_vapi_dep, ocfiles_vapi_dep, ollmchat_vapi_dep, ocvector_vapi_dep, ocmarkdown_vapi_dep],
  sources: occoder_src,
  vala_header: 'occoder.h',
  vala_vapi: 'occoder-meson.vapi',  # Use different name so our custom_target can use 'occoder.vapi'
  vala_gir: 'OLLMcoder-1.0.gir',
  build_rpath: lib_build_rpath,
  include_directories: [
    include_directories('..' / 'libollmchat'),
    include_directories('..' / 'libollamaweb'),
    include_directories('..' / 'libocvector'),   # For C headers (build directory)
    include_directories('..' / 'libocfiles')     # For C headers (build directory)
  ],
  vala_args: [
    '--pkg=sqlite3',
    '--pkg=ocsqlite',
    '--pkg=json-glib-1.0',
    '--pkg=libsoup-3.0',  # Required for ollmchat.vapi (Soup.Message, Soup.Session)
    '--pkg=gmodule-2.0',  # Required for ocfiles (TreeBase uses GModule)
    '--pkg=tree-sitter',  # Required for ocfiles (TreeBase uses TreeSitter)
    '--pkg=fiass',  # Required for ocvector.vapi (Faiss.IDSelector)
    '--pkg=gtk4',
    '--pkg=libadwaita-1',
    '--pkg=gtksourceview-5',
    '--pkg=libgit2-glib-1.0',
    '--pkg=ocfiles',
    '--pkg=ollmchat',
    '--pkg=ollamaweb',
    '--pkg=ocmarkdown',
    '--pkg=ocvector',
    # Put build directories FIRST so we use local VAPIs instead of installed ones
    '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
    '--vapidir', meson.current_build_dir() / '..' / 'libollamaweb',
    '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdown',
    '--vapidir', meson.current_build_dir() / '..' / 'liboctools',
    '--vapidir', meson.current_build_dir() / '..' / 'libocvector',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libocfiles',
    '--vapidir', '/usr/share/vala/vapi',  # System VAPI directory for libgit2-glib-1.0 (last, so local takes priority)
    '--girdir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--girdir', meson.current_build_dir() / '..' / 'libocfiles',
    '--girdir', meson.current_build_dir() / '..' / 'libocmarkdown',
    '--girdir', meson.current_build_dir() / '..' / 'libollmchat',
  ],
  install: true
)

# Manually generate occoder.vapi with correct command line order
occoder_vapi = custom_target('occoder-vapi',
  output: 'occoder.vapi',
  input: occoder_src,
  command: [
    valac_exe,
    '-C', '--debug',
    '--target-glib=auto',
  ] + sqgi_vala_args + [
    # Put build directories FIRST so we use local VAPIs instead of installed ones
    '--vapidir', meson.current_source_dir() / '../vapi',  # Source VAPIs first (fiass.vapi, tree-sitter.vapi)
    '--vapidir', meson.current_source_dir() / '../../vapi',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libocfiles',
    '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
    '--vapidir', meson.current_build_dir() / '..' / 'libollamaweb',
    '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdown',
    '--vapidir', meson.current_build_dir() / '..' / 'libocvector',
    '--vapidir', meson.current_build_dir(),
    '--vapidir', '/usr/share/vala/vapi',  # System VAPI directory for libgit2-glib-1.0 (last, so local takes priority)
    '--pkg', 'posix',
    '--pkg', 'sqlite3',
    '--pkg', 'ocsqlite',
    '--pkg', 'gmodule-2.0',  # Required for ocfiles (TreeBase uses GModule)
    '--pkg', 'tree-sitter',  # Required for ocfiles (TreeBase uses TreeSitter)
    '--pkg', 'ocfiles',
    '--pkg', 'libsoup-3.0',  # Required for ollmchat.vapi (Soup.Message, Soup.Session)
    '--pkg', 'ollmchat',
    '--pkg', 'ollamaweb',
    '--pkg', 'ocmarkdown',
    '--pkg', 'fiass',  # Required for ocvector.vapi (Faiss.IDSelector)
    '--pkg', 'ocvector',
    '--pkg', 'gtk4',  # Required for Tool namespace
    '--pkg', 'libadwaita-1',
    '--pkg', 'gtksourceview-5',
    '--pkg', 'gobject-2.0',
    '--pkg', 'glib-2.0',
    '--pkg', 'gio-2.0',
    '--pkg', 'json-glib-1.0',
    '--pkg', 'gee-0.8',
    '--pkg', 'gtk4',
    '--pkg', 'gtksourceview-5',
    '--pkg', 'libgit2-glib-1.0',
    '--library', 'occoder',
    '--header', meson.current_build_dir() / 'occoder.h',  # Use header from library
    '--vapi', '@OUTPUT@',
    '@INPUT@'
  ],
  depends: [occoder_base_lib, ocfiles_vapi, ollmchat_base_lib, ollamaweb_vapi, ocmarkdown_vapi, ocvector_vapi],
  build_by_default: true,
  install: true,
  install_dir: get_option('datadir') / 'vala' / 'vapi'
)

occoder_gir_file = meson.current_build_dir() / 'OLLMcoder-1.0.gir'
occoder_gir_fixed = meson.current_build_dir() / 'OLLMcoder-1.0.fixed.gir'
fix_gir_dep_names = meson.project_source_root() / 'scripts/fix-gir-dep-names.sed'
custom_target('occoder-typelib',
  output: 'OLLMcoder-1.0.typelib',
  command: [
    find_program('sh'),
    meson.project_source_root() / 'scripts/compile-gir-typelib.sh',
    occoder_gir_file,
    occoder_gir_fixed,
    '@OUTPUT@',
    fix_gir_dep_names,
    '--includedir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--includedir', meson.current_build_dir() / '..' / 'libocfiles',
    '--includedir', meson.current_build_dir() / '..' / 'libocmarkdown',
    '--includedir', meson.current_build_dir() / '..' / 'libollmchat',
    '--includedir', '/usr/share/gir-1.0',
  ],
  depends: occoder_base_lib,
  build_by_default: true,
  install: true,
  install_dir: get_option('libdir') / 'girepository-1.0',
)
meson.add_install_script(
  'sh', '-c',
  'install -Dm644 "' + occoder_gir_file + '" "$DESTDIR$MESON_INSTALL_PREFIX/share/gir-1.0/OLLMcoder-1.0.gir"',
)

# Create dependency for other libraries to use
# Use link_args instead of link_with to prevent meson from auto-including occoder-meson.vapi
occoder_vapi_dep = declare_dependency(
  link_args: ['-L' + meson.current_build_dir(), '-loccoder'],
  sources: [occoder_vapi[0]],  # Include VAPI file to ensure it's built first
  dependencies: [ocsqlite_vapi_dep, ocfiles_vapi_dep]  # Temporarily removed ocvector_vapi_dep, ollmchat_vapi_dep - only needed for CodebaseSearchTool
)
