# Build ocvector library (libocvector.so) - depends on libocsqlite, libollmchat, libocfiles
# Provides semantic codebase search using vector embeddings and FAISS

# Dependencies for ocvector library
valac = meson.get_compiler('vala')
cc = meson.get_compiler('c')

# Find FAISS library (static library, C++ based)
faiss_lib = cc.find_library('faiss',
	 dirs: ['/usr/lib/x86_64-linux-gnu'], required: true)
cpp = meson.get_compiler('cpp')
cpp_std_lib = cpp.find_library('stdc++', required: true)
# FAISS uses OpenMP for parallelization
omp_dep = dependency('openmp', required: true)
# FAISS uses BLAS for matrix operations
blas_dep = dependency('blas', required: true)
# Find tree-sitter library (C library for parsing)
# Tree-sitter provides pkg-config support
tree_sitter_lib = dependency('tree-sitter', required: true)

# Our minimal C wrapper for FAISS C++ API
faiss_wrapper_src = files('faiss_c_wrapper.cpp')
faiss_wrapper_hdr = files('faiss_c_wrapper.h')

ocvector_deps = [
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('gmodule-2.0'),  # GModule for dynamic library loading
  dependency('json-glib-1.0'),
  dependency('libsoup-3.0'),
  dependency('sqlite3'),
  valac.find_library('posix'),
  faiss_lib,
  cpp_std_lib,
  tree_sitter_lib  # Tree-sitter C library (required - Tree.vala uses TreeSitter API)
  # Note: OpenMP and BLAS added via link_args to avoid Vala package issues
]

# Source files for OLLMvector namespace
# Note: Files will be added as they are created in subsequent phases
# Note: namespace.vala files are NOT included here - they're only used for valadoc documentation
ocvector_src = files([
  # Core components (migrated from VectorSearch/)
  'Index.vala',      # FAISS integration
  'Database.vala',  # Vector database with embeddings
  
  # Base class
  'VectorBase.vala',  # Base class for vector operations with tool config access
  
  # VectorMetadata moved to libocfiles (OLLMfiles.SQT.VectorMetadata)
  
  # Files/ directory removed - now using libocfiles instead
  # No need to copy Files classes - use OLLMfiles namespace from libocfiles
  
  # Indexing/ directory
  'Indexing/Tree.vala',  # Tree-sitter AST parsing and VectorMetadata creation
  'Indexing/PromptTemplate.vala',  # Prompt template class for loading and filling templates
  'Indexing/Analysis.vala',  # Code analysis layer
  'Indexing/VectorBuilder.vala',  # Vector generation and FAISS storage
  'Indexing/DocumentationTree.vala',  # Documentation parsing and VectorMetadata creation
  'Indexing/DocumentationAnalysis.vala',  # Documentation analysis layer
  'Indexing/FolderAnalysis.vala',  # Folder analysis layer
  'Indexing/ProjectAnalysis.vala',  # Project summary and dependency extraction
  'Indexing/ImageAnalyzer.vala',  # Image analysis (2.20.3)
  'Indexing/DocumentationVectorBuilder.vala',  # Documentation vector generation and FAISS storage
  'Indexing/Indexer.vala',  # Main indexing orchestrator
  
  # Search/ directory
  'Search/Search.vala',  # Vector search execution
  'Search/SearchResult.vala',  # Search result representation
  
  # Tool/ directory
  'Tool/CodebaseSearchTool.vala',
  'Tool/CodebaseSearchToolConfig.vala',
  'Tool/RequestCodebaseSearch.vala',
  'Registry.vala',
  
  # Background scanning
  'BackgroundScan.vala',  # Background file indexing thread
])

# Build rpath for libraries to find each other in build directory
lib_build_rpath = ':'.join([
  meson.current_build_dir(),
  meson.current_build_dir() / '..' / 'libocsqlite',
  meson.current_build_dir() / '..' / 'libocfiles',
  meson.current_build_dir() / '..' / 'libollmchat',
  meson.current_build_dir() / '..' / 'libollamaweb',
])

# Build the library
ocvector_base_lib = library('ocvector',
  dependencies: [ocvector_deps, ocsqlite_vapi_dep, ollmchat_vapi_dep, ocfiles_vapi_dep],
  sources: ocvector_src + faiss_wrapper_src,
  link_with: [ollmchat_base_lib],  # Need to link with ollmchat_base_lib because CodebaseSearchTool extends OLLMchat.Tool.BaseTool (similar to libollmchatgtk)
  link_args: ['-lblas', '-llapack', '-lgomp'],  # Add BLAS, LAPACK, and OpenMP directly to linker
  vala_header: 'ocvector.h',
  vala_vapi: 'ocvector-meson.vapi',  # Use different name so our custom_target can use 'ocvector.vapi'
  build_rpath: lib_build_rpath,
  include_directories: [
    include_directories('.'),
    include_directories('..' / 'libollmchat'),
    include_directories('..' / 'libollamaweb'),
    include_directories('..' / 'libocsqlite'),
    include_directories('..' / 'libocfiles'),
  ],
  vala_args: [
    '--pkg=sqlite3',
    '--pkg=json-glib-1.0',
    '--pkg=libsoup-3.0',
    '--pkg=gmodule-2.0',  # GModule for dynamic library loading
    '--pkg=fiass',  # FAISS via vapi
    '--pkg=tree-sitter',  # Tree-sitter via vapi
    '--pkg=ocfiles',
    '--pkg=ollmchat',
    '--pkg=ollamaweb',
    '--pkg=ocsqlite',
    '--vapidir', meson.current_source_dir() / '../vapi',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libocfiles',
    '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
    '--vapidir', meson.current_build_dir() / '..' / 'libollamaweb',
  ],
  install: true
)

# Manually generate ocvector.vapi with correct --pkg order (installed as ocvector.vapi).
#
# Meson also emits ocvector-meson.vapi from library(). Do NOT delete that file: ninja
# tracks it as a library output, so deleting it forces a full ocvector rebuild every run.
#
# The old ocvector-meson-vapi-deleted target removed it so this custom_target could add
# --vapidir=build/libocvector without duplicate-type errors. Instead we omit that vapidir
# here (header path is explicit below). Downstream uses --pkg=ocvector + ocvector_vapi_dep
# (link_args), not link_with: [ocvector_base_lib], so they never pick up ocvector-meson.vapi.
ocvector_vapi = custom_target('ocvector-vapi',
  output: 'ocvector.vapi',
  input: ocvector_src,
  command: [
    valac_exe,
    '-C', '--debug',
    '--target-glib=auto',
    # Put build directories FIRST so we use local VAPIs instead of installed ones
    '--vapidir', meson.current_source_dir() / '../vapi',  # Source VAPIs first (fiass.vapi, tree-sitter.vapi)
    '--vapidir', meson.current_source_dir() / '../../vapi',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libocfiles',
    '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
    '--vapidir', meson.current_build_dir() / '..' / 'libollamaweb',
    '--vapidir', '/usr/share/vala/vapi',  # System VAPI directory (last, so local takes priority)
    '--pkg', 'posix',
    '--pkg', 'sqlite3',
    '--pkg', 'json-glib-1.0',
    '--pkg', 'libsoup-3.0',
    '--pkg', 'gmodule-2.0',
    '--pkg', 'fiass',  # FAISS via vapi
    '--pkg', 'tree-sitter',  # Tree-sitter via vapi
    '--pkg', 'ocfiles',
    '--pkg', 'ollmchat',
    '--pkg', 'ollamaweb',
    '--pkg', 'ocsqlite',
    '--pkg', 'gobject-2.0',
    '--pkg', 'glib-2.0',
    '--pkg', 'gio-2.0',
    '--pkg', 'gee-0.8',
    '--header', meson.current_build_dir() / 'ocvector.h',  # Use header from library
    '--vapi', '@OUTPUT@',
    '@INPUT@'
  ],
  depends: [ocvector_base_lib, ollamaweb_vapi],  # ollmchat.vapi needs ollamaweb.vapi
  build_by_default: true,
  install: true,
  install_dir: get_option('datadir') / 'vala' / 'vapi'
)

# Create dependency for other libraries to use
# Use link_args instead of link_with to prevent meson from auto-including ocvector-meson.vapi
# Note: When targets use link_with: [ocvector_base_lib], meson will include ocvector-meson.vapi.
# The custom_target ensures ocvector.vapi exists and is found via --pkg=ocvector, but we don't
# include it in sources to avoid conflicts when linking with the library directly.
ocvector_vapi_dep = declare_dependency(
  link_args: ['-L' + meson.current_build_dir(), '-locvector'],
  sources: [ocvector_vapi[0]],  # Include VAPI file to ensure it's built first
  dependencies: [ocsqlite_vapi_dep, ollmchat_vapi_dep, ocfiles_vapi_dep]
)

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
