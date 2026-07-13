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
  valac.find_library('posix'),
]

occoder_src = files([
  'BufferProvider.vala',
  'GtkSourceFileBuffer.vala',
  'SearchableDropdown.vala',
  'ProjectDropdown.vala',
  'FileDropdown.vala',
  'SourceView.vala',
  'AgentFactory.vala',
  'Agent.vala',
  'Skill/PromptTemplate.vala',
  'Skill/Definition.vala',
  'Skill/Manager.vala',
  'Skill/Factory.vala',
  'Task/PhaseEnum.vala',
  'Task/ProgressItem.vala',
  'Task/ProgressRunner.vala',
  'Task/Step.vala',
  'Task/Details.vala',
  'Task/ValidateLink.vala',
  'Task/ResolveLink.vala',
  'Task/Tool.vala',
  'Task/ToolList.vala',
  'Task/WriteChange.vala',
  'Task/List.vala',
  'Task/ProgressList.vala',
  'Task/ProgressView.vala',
  'Skill/Runner.vala',
  'Action/Base.vala',
  'Action/PostExamMerge.vala',
  'Action/ExamSequence.vala',
  'Action/RunTools.vala',
  'Action/RefOnly.vala',
  'Action/WriteExec.vala',
  'Task/ResultParser.vala',
  'List/SortedList.vala',
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
  meson.current_build_dir() / '..' / 'liboctools'
])

occoder_lib_deps = [occoder_deps, ocsqlite_vapi_dep, ocfiles_vapi_dep, ollmchat_vapi_dep, ocmarkdown_vapi_dep, ocrpc_vapi_dep]
occoder_vala_args = [
  '--pkg=sqlite3',
  '--pkg=ocsqlite',
  '--pkg=json-glib-1.0',
  '--pkg=libsoup-3.0',
  '--pkg=gmodule-2.0',
  '--pkg=tree-sitter',
  '--pkg=gtk4',
  '--pkg=libadwaita-1',
  '--pkg=gtksourceview-5',
  '--pkg=ocfiles',
  '--pkg=ollmchat',
  '--pkg=ollamaweb',
  '--pkg=ocmarkdown',
  '--pkg=ocrpc',
  '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
  '--vapidir', meson.current_build_dir() / '..' / 'libollamaweb',
  '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdown',
  '--vapidir', meson.current_build_dir() / '..' / 'libocrpc',
  '--vapidir', meson.current_build_dir() / '..' / 'liboctools',
  '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
  '--vapidir', meson.current_build_dir() / '..' / 'libocfiles',
  '--vapidir', '/usr/share/vala/vapi',
  '--girdir', meson.current_build_dir() / '..' / 'libocsqlite',
  '--girdir', meson.current_build_dir() / '..' / 'libocfiles',
  '--girdir', meson.current_build_dir() / '..' / 'libocmarkdown',
  '--girdir', meson.current_build_dir() / '..' / 'libollmchat',
]

occoder_base_lib = library(occoder_lib,
  dependencies: occoder_lib_deps,
  sources: occoder_src,
  vala_header: 'occoder.h',
  vala_vapi: 'occoder-meson.vapi',  # Use different name so our custom_target can use 'occoder.vapi'
  vala_gir: 'OLLMcoder-1.0.gir',
  build_rpath: lib_build_rpath,
  include_directories: [
    include_directories('..' / 'libollmchat'),
    include_directories('..' / 'libollamaweb'),
    include_directories('..' / 'libocfiles')     # For C headers (build directory)
  ],
  vala_args: occoder_vala_args,
  install: true
)

occoder_vapi_gen_pkgs = [
  '--pkg', 'posix',
  '--pkg', 'sqlite3',
  '--pkg', 'ocsqlite',
  '--pkg', 'gmodule-2.0',
  '--pkg', 'tree-sitter',
  '--pkg', 'ocfiles',
  '--pkg', 'libsoup-3.0',
  '--pkg', 'ollmchat',
  '--pkg', 'ollamaweb',
  '--pkg', 'ocmarkdown',
  '--pkg', 'gtk4',
  '--pkg', 'libadwaita-1',
  '--pkg', 'gtksourceview-5',
  '--pkg', 'gobject-2.0',
  '--pkg', 'glib-2.0',
  '--pkg', 'gio-2.0',
  '--pkg', 'json-glib-1.0',
  '--pkg', 'gee-0.8',
]
occoder_vapi_gen_pkgs += ['--pkg', 'ocrpc']

occoder_vapi_vapidirs = [
  '--vapidir', meson.current_source_dir() / '../vapi',
  '--vapidir', meson.current_source_dir() / '../../vapi',
  '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
  '--vapidir', meson.current_build_dir() / '..' / 'libocfiles',
  '--vapidir', meson.current_build_dir() / '..' / 'libocrpc',
  '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
  '--vapidir', meson.current_build_dir() / '..' / 'libollamaweb',
  '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdown',
  '--vapidir', meson.current_build_dir(),
  '--vapidir', '/usr/share/vala/vapi',
]

occoder_vapi_depends = [occoder_base_lib, ocfiles_vapi, ollmchat_base_lib, ollamaweb_vapi, ocmarkdown_vapi, ocrpc_vapi]

# Manually generate occoder.vapi with correct command line order
occoder_vapi = custom_target('occoder-vapi',
  output: 'occoder.vapi',
  input: occoder_src,
  command: [
    valac_exe,
    '-C', '--debug',
    '--target-glib=auto',
  ] + sqgi_vala_args + occoder_vapi_vapidirs + occoder_vapi_gen_pkgs + [
    '--library', occoder_lib,
    '--header', meson.current_build_dir() / 'occoder.h',
    '--vapi', '@OUTPUT@',
    '@INPUT@'
  ],
  depends: occoder_vapi_depends,
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
  link_args: ['-L' + meson.current_build_dir(), '-l' + occoder_lib],
  sources: [occoder_vapi[0]],  # Include VAPI file to ensure it's built first
  dependencies: [ocsqlite_vapi_dep, ocfiles_vapi_dep]  # Temporarily removed ocvector_vapi_dep, ollmchat_vapi_dep - only needed for CodebaseSearchTool
)
