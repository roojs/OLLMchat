# Build ocfiles library (libocfiles.so) - depends on libocsqlite
# Provides file and project management without GTK/git dependencies

# Dependencies for ocfiles library
valac = meson.get_compiler('vala')
cc = meson.get_compiler('c')
# Find tree-sitter library (C library for parsing)
tree_sitter_lib = dependency('tree-sitter', required: true)
ocfiles_deps = [
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('gmodule-2.0'),  # GModule for dynamic library loading
  dependency('json-glib-1.0'),  # Required for ProjectMigrate (JSON parsing)
  dependency('sqlite3'),
  valac.find_library('posix'),
  tree_sitter_lib,  # Tree-sitter C library (required - TreeBase uses TreeSitter API)
]

ocfiles_src = files([
  'BufferProviderBase.vala',
  'FileBuffer.vala',  # Must come before File.vala (File uses FileBuffer)
  'FileChange.vala',
  'DummyFileBuffer.vala',
  'FileBase.vala',
  'FileHistory.vala',  # Uses FileBase
  'File.vala',
  'FileAlias.vala',
  'Folder.vala',
  'FolderFiles.vala',
  'GitProviderBase.vala',
  'ProjectFile.vala',
  'ProjectFiles.vala',
  'ProjectList.vala',
  'ProjectManager.vala',
  'DeleteManager.vala',  # Uses ProjectManager
  'ProjectMigrate.vala',
  'Tree.vala',  # Tree-sitter base class
  'Diff/Patch.vala',
  'Diff/PatchApplier.vala',
  'Diff/Differ.vala',
])

# Build rpath for libraries to find each other in build directory
lib_build_rpath = ':'.join([
  meson.current_build_dir(),
  meson.current_build_dir() / '..' / 'libocsqlite',
])

ocfiles_base_lib = library('ocfiles',
  dependencies: [ocfiles_deps, ocsqlite_vapi_dep],
  sources: ocfiles_src,
  vala_header: 'ocfiles.h',
  vala_vapi: 'ocfiles-meson.vapi',  # Use different name so our custom_target can use 'ocfiles.vapi'
  build_rpath: lib_build_rpath,
  vala_args: [
    '--pkg=sqlite3',
    '--pkg=json-glib-1.0',  # Required for ProjectMigrate (JSON parsing)
    '--pkg=gmodule-2.0',  # GModule for dynamic library loading (required for TreeBase)
    '--pkg=tree-sitter',  # Tree-sitter via vapi (required for TreeBase)
    '--pkg=ocsqlite',
    # Put build directories FIRST so we use local VAPIs instead of installed ones
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_source_dir() / '../vapi',  # For tree-sitter.vapi
    '--vapidir', '/usr/share/vala/vapi'  # System VAPI directory (last, so local takes priority)
  ],
  install: true
)

# Manually generate ocfiles.vapi with correct command line order
ocfiles_vapi = custom_target('ocfiles-vapi',
  output: 'ocfiles.vapi',
  input: ocfiles_src,
  command: [
    valac_exe,
    '-C', '--debug',
    '--target-glib=auto',
    # Put build directories FIRST so we use local VAPIs instead of installed ones
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir(),
    '--vapidir', meson.current_source_dir() / '../vapi',  # For tree-sitter.vapi
    '--vapidir', meson.current_source_dir() / '../../vapi',
    '--vapidir', '/usr/share/vala/vapi',  # System VAPI directory (last, so local takes priority)
    '--pkg', 'posix',
    '--pkg', 'sqlite3',
    '--pkg', 'json-glib-1.0',  # Required for ProjectMigrate (JSON parsing)
    '--pkg', 'gmodule-2.0',  # GModule for dynamic library loading (required for TreeBase)
    '--pkg', 'tree-sitter',  # Tree-sitter via vapi (required for TreeBase)
    '--pkg', 'ocsqlite',
    '--pkg', 'gobject-2.0',
    '--pkg', 'glib-2.0',
    '--pkg', 'gio-2.0',
    '--pkg', 'gee-0.8',
    '--library', 'ocfiles',
    '--header', meson.current_build_dir() / 'ocfiles.h',  # Use header from library
    '--vapi', '@OUTPUT@',
    '@INPUT@'
  ],
  depends: [ocfiles_base_lib],  # Ensure library is built first (so header exists)
  build_by_default: true,
  install: true,
  install_dir: get_option('datadir') / 'vala' / 'vapi'
)

# Create dependency for other libraries to use
# Use link_args instead of link_with to prevent meson from auto-including ocfiles-meson.vapi
ocfiles_vapi_dep = declare_dependency(
  link_args: ['-L' + meson.current_build_dir(), '-locfiles'],
  sources: [ocfiles_vapi[0]],  # Include VAPI file to ensure it's built first
  dependencies: [ocsqlite_vapi_dep]
)

# GObject Introspection for ocfiles library
ocfiles_gir = gnome.generate_gir(ocfiles_base_lib,
  namespace: 'OLLMfiles',
  nsversion: '1.0',
  identifier_prefix: 'OLLMfiles',
  symbol_prefix: 'ollmfiles',
  link_with: [ocsqlite_base_lib],
  dependencies: [dependency('sqlite3')],
  extra_args: [
    '--extra-library=ocsqlite',
    '--accept-unprefixed'
  ],
  includes: ['GObject-2.0', 'Gio-2.0', ocsqlite_gir[0]],
  install: true,
  fatal_warnings: false
)
