# Build octools library (liboctools.so) - depends on libollmchat, libocfiles
# Provides tools for file operations and other utilities

# Dependencies for octools library
valac = meson.get_compiler('vala')
cc = meson.get_compiler('c')
# Find tree-sitter library (C library for parsing)
tree_sitter_lib = dependency('tree-sitter', required: true)
octools_deps = [
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('gmodule-2.0'),  # GModule for dynamic library loading
  dependency('json-glib-1.0'),
  dependency('libsoup-3.0'),
  valac.find_library('posix'),
  tree_sitter_lib,  # Tree-sitter C library (required - ReadFileSummarize uses TreeSitter API)
]

# Source files for OLLMtools namespace
octools_src = files([
  'ReadFile/Tool.vala',
  'ReadFile/Request.vala',
  'ReadFile/Summarize.vala',
  'EditMode/Tool.vala',
  'EditMode/Request.vala',
  'RunCommand/Tool.vala',
  'RunCommand/Request.vala',
  'WebFetch/Tool.vala',
  'WebFetch/Request.vala',
  'GoogleSearch/Tool.vala',
  'GoogleSearch/Request.vala',
  'GoogleSearch/Config.vala',
  'GoogleSearch/ToolConfig.vala',
])

# Build rpath for libraries to find each other in build directory
lib_build_rpath = ':'.join([
  meson.current_build_dir(),
  meson.current_build_dir() / '..' / 'libocsqlite',
  meson.current_build_dir() / '..' / 'libocfiles',
  meson.current_build_dir() / '..' / 'libollmchat',
])

octools_base_lib = library('octools',
  dependencies: [octools_deps, ollmchat_vapi_dep, ocfiles_vapi_dep, ocmarkdown_vapi_dep],
  sources: octools_src,
  vala_header: 'octools.h',
  vala_vapi: 'octools-meson.vapi',  # Use different name so our custom_target can use 'octools.vapi'
  build_rpath: lib_build_rpath,
  include_directories: [
    include_directories('..' / 'libollmchat'),  # For ollmchat.h header
  ],
  vala_args: [
    '--pkg=ollmchat',
    '--pkg=ocfiles',
    '--pkg=ocsqlite',
    '--pkg=ocmarkdown',
    '--pkg=gmodule-2.0',  # Required for ocfiles (TreeBase uses GModule)
    '--pkg=tree-sitter',  # Required for ocfiles (TreeBase uses TreeSitter)
    '--pkg=json-glib-1.0',
    # Put build directories FIRST so we use local VAPIs instead of installed ones
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libocfiles',
    '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdown',
    '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
    '--vapidir', meson.current_source_dir() / '../vapi',  # For tree-sitter.vapi
    '--vapidir', '/usr/share/vala/vapi'  # System VAPI directory (last, so local takes priority)
  ],
  install: true
)

# Manually generate octools.vapi with correct command line order
octools_vapi = custom_target('octools-vapi',
  output: 'octools.vapi',
  input: octools_src,
  command: [
    valac_exe,
    '-C', '--debug',
    '--target-glib=auto',
    # Put build directories FIRST so we use local VAPIs instead of installed ones
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libocfiles',
    '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdown',
    '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
    '--vapidir', meson.current_source_dir() / '../vapi',  # For tree-sitter.vapi
    '--vapidir', '/usr/share/vala/vapi',  # System VAPI directory (last, so local takes priority)
    '--pkg', 'posix',
    '--pkg', 'json-glib-1.0',
    '--pkg', 'libsoup-3.0',
    '--pkg', 'gmodule-2.0',  # Required for ocfiles (TreeBase uses GModule)
    '--pkg', 'tree-sitter',  # Required for ocfiles (TreeBase uses TreeSitter)
    '--pkg', 'sqlite3',  # Required for ocsqlite.vapi (Sqlite namespace)
    '--pkg', 'ollmchat',
    '--pkg', 'ocfiles',
    '--pkg', 'ocmarkdown',
    '--pkg', 'ocsqlite',
    '--pkg', 'gobject-2.0',
    '--pkg', 'glib-2.0',
    '--pkg', 'gio-2.0',
    '--pkg', 'gee-0.8',
    '--library', 'octools',
    '--header', meson.current_build_dir() / 'octools.h',  # Use header from library
    '--vapi', '@OUTPUT@',
    '@INPUT@'
  ],
  depends: [octools_base_lib],  # Ensure library is built first (so header exists)
  build_by_default: true,
  install: true,
  install_dir: get_option('datadir') / 'vala' / 'vapi'
)

# Create dependency for other libraries to use
# Use link_args instead of link_with to prevent meson from auto-including octools-meson.vapi
octools_vapi_dep = declare_dependency(
  link_args: ['-L' + meson.current_build_dir(), '-loctools'],
  sources: [octools_vapi[0]],  # Include VAPI file to ensure it's built first
  dependencies: [ollmchat_vapi_dep, ocfiles_vapi_dep, ocmarkdown_vapi_dep]
)

# GObject Introspection for octools library
octools_gir = gnome.generate_gir(octools_base_lib,
  namespace: 'OLLMtools',
  nsversion: '1.0',
  identifier_prefix: 'OLLMtools',
  symbol_prefix: 'ollmtools',
  link_with: [ollmchat_base_lib, ocfiles_base_lib],
  dependencies: [],
  extra_args: [
    '--extra-library=ollmchat',
    '--extra-library=ocfiles',
    '--accept-unprefixed'
  ],
  includes: ['GObject-2.0', 'Gio-2.0', 'Json-1.0', ollmchat_gir[0], ocfiles_gir[0]],
  install: true,
  fatal_warnings: false
)

