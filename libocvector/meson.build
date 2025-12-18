# Build ocvector library (libocvector.so) - depends on libocsqlite, libollmchat
# Provides semantic codebase search using vector embeddings and FAISS

# Dependencies for ocvector library
valac = meson.get_compiler('vala')
ocvector_deps = [
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('json-glib-1.0'),
  dependency('libsoup-3.0'),
  dependency('sqlite3'),
  valac.find_library('posix'),
]

# Source files for OLLMvector namespace
# Note: Files will be added as they are created in subsequent phases
ocvector_src = files([
  # Core components (to be migrated from VectorSearch/)
  'Index.vala',  # FAISS namespace - placeholder for Phase 1
  
  # Files/ directory (copied from liboccoder, namespace: OLLMvector.Files)
  # 'Files/FileBase.vala',
  # 'Files/File.vala',
  # 'Files/Folder.vala',
  
  # Indexing/ directory
  # 'Indexing/Analysis.vala',
  # 'Indexing/VectorBuilder.vala',
  # 'Indexing/Indexer.vala',
  
  # Search/ directory
  # 'Search/Searcher.vala',
  # 'Search/QueryProcessor.vala',
  
  # Tool/ directory
  # 'Tool/CodebaseSearchTool.vala',
  
  # 'Database.vala',
])

# Build rpath for libraries to find each other in build directory
lib_build_rpath = ':'.join([
  meson.current_build_dir(),
  meson.current_build_dir() / '..' / 'libocsqlite',
  meson.current_build_dir() / '..' / 'libollmchat',
])

# Build the library
# Note: Dependencies on ocsqlite_vapi_dep and ollmchat_vapi_dep will be added
# when those libraries are available in the build context
ocvector_base_lib = library('ocvector',
  dependencies: [ocvector_deps],  # ocsqlite_vapi_dep, ollmchat_vapi_dep will be added later
  sources: ocvector_src,
  vala_header: 'ocvector.h',
  vala_vapi: 'ocvector-meson.vapi',  # Use different name so our custom_target can use 'ocvector.vapi'
  build_rpath: lib_build_rpath,
  vala_args: [
    '--pkg=sqlite3',
    '--pkg=json-glib-1.0',
    '--pkg=libsoup-3.0',
    '--vapidir', meson.current_source_dir() / '../vapi',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
  ],
  install: true
)

# Manually generate ocvector.vapi with correct command line order
# This will be enabled once we have source files
# ocvector_vapi = custom_target('ocvector-vapi',
#   output: 'ocvector.vapi',
#   input: ocvector_src,
#   command: [
#     valac_exe,
#     '-C', '--debug',
#     '--target-glib=auto',
#     '--vapidir', meson.current_source_dir() / '../vapi',
#     '--vapidir', meson.current_source_dir() / '../../vapi',
#     '--vapidir', meson.current_build_dir(),
#     '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
#     '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
#     '--pkg', 'posix',
#     '--pkg', 'sqlite3',
#     '--pkg', 'json-glib-1.0',
#     '--pkg', 'libsoup-3.0',
#     '--pkg', 'fiass',  # FAISS via vapi
#     '--pkg', 'ocsqlite',
#     '--pkg', 'ollmchat',
#     '--pkg', 'gobject-2.0',
#     '--pkg', 'glib-2.0',
#     '--pkg', 'gio-2.0',
#     '--pkg', 'gee-0.8',
#     '--library', 'ocvector',
#     '--header', meson.current_build_dir() / 'ocvector.h',
#     '--vapi', '@OUTPUT@',
#     '@INPUT@'
#   ],
#   depends: [ocvector_base_lib],
#   build_by_default: true,
#   install: true,
#   install_dir: get_option('datadir') / 'vala' / 'vapi'
# )

# Create a dependency that includes the VAPI file to ensure build order
# This will be enabled once we have source files and VAPI generation
# ocvector_vapi_dep = declare_dependency(
#   link_args: ['-L' + meson.current_build_dir(), '-locvector'],
#   sources: [ocvector_vapi[0]],
#   dependencies: [dependency('sqlite3')]
# )

# GObject Introspection for ocvector library
# This will be enabled once we have source files
# ocvector_gir = gnome.generate_gir(ocvector_base_lib,
#   namespace: 'OLLMvector',
#   nsversion: '1.0',
#   identifier_prefix: 'OLLMvector',
#   symbol_prefix: 'ocvector',
#   link_with: [ocsqlite_base_lib, ollmchat_base_lib],
#   dependencies: [dependency('sqlite3')],
#   extra_args: [
#     '--extra-library=ocsqlite',
#     '--extra-library=ollmchat',
#     '--accept-unprefixed'
#   ],
#   includes: ['GObject-2.0', 'Gio-2.0', 'Json-1.0', ocsqlite_gir[0], ollmchat_gir[0]],
#   install: true,
#   fatal_warnings: false
# )
