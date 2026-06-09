# Build octools library (liboctools.so) - depends on libollmchat, libocfiles
# Provides tools for file operations and other utilities

# Dependencies for octools library
valac = meson.get_compiler('vala')
cc = meson.get_compiler('c')
# tree-sitter: resolved in config/meson.build
octools_deps = [
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('gmodule-2.0'),  # GModule for dynamic library loading
  dependency('json-glib-1.0'),
  dependency('libsoup-3.0'),
  valac.find_library('posix'),
  tree_sitter_dep,
]

# Source files for OLLMtools namespace
octools_src = files([
  'ReadFile/Tool.vala',
  'ReadFile/Request.vala',
  'ReadFile/Summarize.vala',
  'EditMode/Tool.vala',
  'EditMode/Request.vala',
  'EditMode/Stream.vala',
  'WriteFile/Tool.vala',
  'WriteFile/Request.vala',
  'RunCommand/Tool.vala',
  'RunCommand/Request.vala',
  'WebFetch/Tool.vala',
  'WebFetch/Request.vala',
  'GoogleSearch/Tool.vala',
  'GoogleSearch/Request.vala',
  'GoogleSearch/Config.vala',
  'ToolBuilder.vala',
  'Registry.vala',
  'Child/Parser.vala',
  'Child/Tool.vala',
  'Child/Factory.vala',
  'Child/Agent.vala',
  'Child/Request.vala',
  'Child/Config.vala',
])

# Build rpath for libraries to find each other in build directory
lib_build_rpath = ':'.join([
  meson.current_build_dir(),
  meson.current_build_dir() / '..' / 'libocsqlite',
  meson.current_build_dir() / '..' / 'libocfiles',
  meson.current_build_dir() / '..' / 'libollmchat',
  meson.current_build_dir() / '..' / 'libollamaweb',
])

octools_base_lib = library('octools',
  dependencies: [octools_deps, ollmchat_vapi_dep, ocfiles_vapi_dep, ocmarkdown_vapi_dep],
  sources: octools_src,
  vala_header: 'octools.h',
  vala_vapi: 'octools-meson.vapi',  # Use different name so our custom_target can use 'octools.vapi'
  vala_gir: 'OLLMtools-1.0.gir',
  build_rpath: lib_build_rpath,
  include_directories: [
    include_directories('..' / 'libollmchat'),
    include_directories('..' / 'libollamaweb'),
  ],
  vala_args: [
    '--pkg=ollmchat',
    '--pkg=ollamaweb',
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
    '--vapidir', meson.current_build_dir() / '..' / 'libollamaweb',
    '--vapidir', meson.current_source_dir() / '../vapi',  # For tree-sitter.vapi
    '--vapidir', '/usr/share/vala/vapi',  # System VAPI directory (last, so local takes priority)
    '--girdir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--girdir', meson.current_build_dir() / '..' / 'libocfiles',
    '--girdir', meson.current_build_dir() / '..' / 'libocmarkdown',
    '--girdir', meson.current_build_dir() / '..' / 'libollmchat',
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
    '--vapidir', meson.current_build_dir() / '..' / 'libollamaweb',
    '--vapidir', meson.current_source_dir() / '../vapi',  # For tree-sitter.vapi
    '--vapidir', '/usr/share/vala/vapi',  # System VAPI directory (last, so local takes priority)
    '--pkg', 'posix',
    '--pkg', 'json-glib-1.0',
    '--pkg', 'libsoup-3.0',
    '--pkg', 'gmodule-2.0',  # Required for ocfiles (TreeBase uses GModule)
    '--pkg', 'tree-sitter',  # Required for ocfiles (TreeBase uses TreeSitter)
    '--pkg', 'sqlite3',  # Required for ocsqlite.vapi (Sqlite namespace)
    '--pkg', 'ollmchat',
    '--pkg', 'ollamaweb',
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
  depends: [octools_base_lib, ollamaweb_vapi],
  build_by_default: true,
  install: true,
  install_dir: get_option('datadir') / 'vala' / 'vapi'
)

# Create dependency for other libraries to use
# Use link_args instead of link_with to prevent meson from auto-including octools-meson.vapi
octools_vapi_dep = declare_dependency(
  link_args: ['-L' + meson.current_build_dir(), '-loctools'],
  sources: [octools_vapi[0]],  # Include VAPI file to ensure it's built first
  dependencies: [ollmchat_vapi_dep, ocfiles_vapi_dep, ocmarkdown_vapi_dep, octools_deps]
)

octools_gir_file = meson.current_build_dir() / 'OLLMtools-1.0.gir'
octools_gir_fixed = meson.current_build_dir() / 'OLLMtools-1.0.fixed.gir'
fix_gir_dep_names = meson.project_source_root() / 'scripts/fix-gir-dep-names.sed'
custom_target('octools-typelib',
  output: 'OLLMtools-1.0.typelib',
  command: [
    find_program('sh'),
    meson.project_source_root() / 'scripts/compile-gir-typelib.sh',
    octools_gir_file,
    octools_gir_fixed,
    '@OUTPUT@',
    fix_gir_dep_names,
    '--includedir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--includedir', meson.current_build_dir() / '..' / 'libocfiles',
    '--includedir', meson.current_build_dir() / '..' / 'libocmarkdown',
    '--includedir', meson.current_build_dir() / '..' / 'libollmchat',
    '--includedir', '/usr/share/gir-1.0',
  ],
  depends: octools_base_lib,
  build_by_default: true,
  install: true,
  install_dir: get_option('libdir') / 'girepository-1.0',
)
meson.add_install_script(
  'sh', '-c',
  'install -Dm644 "' + octools_gir_file + '" "$DESTDIR$MESON_INSTALL_PREFIX/share/gir-1.0/OLLMtools-1.0.gir"',
)
