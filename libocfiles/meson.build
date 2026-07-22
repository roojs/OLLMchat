# Build ocfiles library (libocfiles.so) - depends on libocsqlite
# Provides file and project management without GTK/git dependencies

# Dependencies for ocfiles library
valac = meson.get_compiler('vala')
cc = meson.get_compiler('c')
is_windows = host_machine.system() == 'windows'
# tree-sitter: resolved in config/meson.build
ocfiles_deps = [
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('gmodule-2.0'),  # GModule for dynamic library loading
  dependency('json-glib-1.0'),
  dependency('sqlite3'),
  valac.find_library('posix'),
  tree_sitter_dep,
]

ocfiles_vapi_pkgs = [
  '--pkg=sqlite3',
  '--pkg=json-glib-1.0',
  '--pkg=gmodule-2.0',  # GModule for dynamic library loading (required for TreeBase)
  '--pkg=tree-sitter',  # Tree-sitter via vapi (required for TreeBase)
  '--pkg=ocsqlite',
]

ocfiles_vapi_gen_pkgs = [
  '--pkg', 'posix',
  '--pkg', 'sqlite3',
  '--pkg', 'json-glib-1.0',
  '--pkg', 'gmodule-2.0',  # GModule for dynamic library loading (required for TreeBase)
  '--pkg', 'tree-sitter',  # Tree-sitter via vapi (required for TreeBase)
  '--pkg', 'ocsqlite',
  '--pkg', 'gobject-2.0',
  '--pkg', 'glib-2.0',
  '--pkg', 'gio-2.0',
  '--pkg', 'gee-0.8',
]

ocfiles_src = files([
  'BufferProviderBase.vala',
  'FileBuffer.vala',
  'DummyFileBuffer.vala',
  'FileChange.vala',
  'FileHistory.vala',
  'FileAlias.vala',
  'FileWithHistory.vala',
  'GitProviderBase.vala',
  'Copyable.vala',
  meson.current_source_dir() / '../ollmfilesd/CallParam.vala',
  'Diff/Patch.vala',
  'Diff/PatchApplier.vala',
  'Diff/Differ.vala',
  'SQT/VectorMetadata.vala',
  'FileBase.vala',
  'File.vala',
  'Folder.vala',
  'FolderFiles.vala',
  'ProjectFile.vala',
  'ProjectFiles.vala',
  'ReviewFiles.vala',
  'ProjectList.vala',
  'ProjectManager.vala',
  'DeleteManager.vala',
  'TreeBase.vala',
  'Tree.vala',
])

# Build rpath for libraries to find each other in build directory
lib_build_rpath = ':'.join([
  meson.current_build_dir(),
  meson.current_build_dir() / '..' / 'libocsqlite',
  meson.current_build_dir() / '..' / 'libocrpc',
])

ocfiles_lib_deps = [ocfiles_deps, ocrpc_vapi_dep, ocsqlite_vapi_dep]

ocfiles_lib_vala_args = ocfiles_vapi_pkgs + ['--pkg=ocrpc'] + strcasestr_vala_args + [
  # Put build directories FIRST so we use local VAPIs instead of installed ones
  '--vapidir', meson.current_build_dir() / '..' / 'libocrpc',
  '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
  '--vapidir', meson.current_source_dir() / '../vapi',  # For tree-sitter.vapi
  '--girdir', meson.current_build_dir() / '..' / 'libocsqlite',
]
if not is_windows
  ocfiles_lib_vala_args += ['--vapidir', '/usr/share/vala/vapi']
endif

ocfiles_base_lib = library(ocfiles_lib,
  dependencies: ocfiles_lib_deps,
  sources: ocfiles_src,
  vala_header: 'ocfiles.h',
  vala_vapi: 'ocfiles-meson.vapi',  # Use different name so our custom_target can use 'ocfiles.vapi'
  # No vala_gir — MSYS2 Meson 1.11 rejects vala_gir: [] (wants str or omit).
  build_rpath: lib_build_rpath,
  include_directories: [
    include_directories('..' / 'vapi'),
  ],
  vala_args: ocfiles_lib_vala_args,
  install: true
)

# Manually generate ocfiles.vapi with correct command line order
ocfiles_vapi_cmd = [
  valac_exe,
  '-C', '--debug',
  '--target-glib=auto',
  # Put build directories FIRST so we use local VAPIs instead of installed ones
  '--vapidir', meson.current_build_dir() / '..' / 'libocrpc',
  '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
  '--vapidir', meson.current_build_dir(),
  '--vapidir', meson.current_source_dir() / '../vapi',  # For tree-sitter.vapi
  '--vapidir', meson.current_source_dir() / '../../vapi',
]
if not is_windows
  ocfiles_vapi_cmd += ['--vapidir', '/usr/share/vala/vapi']
endif
ocfiles_vapi = custom_target('ocfiles-vapi',
  output: 'ocfiles.vapi',
  input: ocfiles_src,
  command: ocfiles_vapi_cmd + ['--pkg', 'ocrpc'] + ocfiles_vapi_gen_pkgs + strcasestr_vala_args + [
    '--library', ocfiles_lib,
    '--header', meson.current_build_dir() / 'ocfiles.h',  # Use header from library
    '--vapi', '@OUTPUT@',
    '@INPUT@'
  ],
  depends: [ocfiles_base_lib, ocrpc_vapi],
  build_by_default: true,
  install: true,
  install_dir: get_option('datadir') / 'vala' / 'vapi'
)

ocfiles_vapi_dep_deps = [ocrpc_vapi_dep, ocsqlite_vapi_dep, ocfiles_deps]

# Create dependency for other libraries to use
# Use link_args instead of link_with to prevent meson from auto-including ocfiles-meson.vapi
ocfiles_vapi_dep = declare_dependency(
  link_args: ['-L' + meson.current_build_dir(), '-l' + ocfiles_lib],
  sources: [ocfiles_vapi[0]],  # Include VAPI file to ensure it's built first
  dependencies: ocfiles_vapi_dep_deps
)
