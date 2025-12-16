# Build ocagent library (libocagent.so) - no dependencies
# This library handles prompt modification and agent interfaces

# Dependencies for ocagent library
valac = meson.get_compiler('vala')
ocagent_deps = [
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('json-glib-1.0'),
  valac.find_library('posix'),
]

ocagent_src = files([
  'BaseAgent.vala',
  'JustAsk.vala',
])

# Build rpath for libraries to find each other in build directory
lib_build_rpath = ':'.join([
  meson.current_build_dir()
])

ocagent_base_lib = library('ocagent',
  dependencies: [ocagent_deps],
  sources: ocagent_src,
  vala_header: 'ocagent.h',
  vala_vapi: 'ocagent-meson.vapi',
  build_rpath: lib_build_rpath,
  vala_args: [
    '--pkg=gee-0.8',
    '--pkg=gobject-2.0',
    '--pkg=glib-2.0',
    '--pkg=gio-2.0',
    '--pkg=json-glib-1.0',
  ],
  install: true
)

# Manually generate ocagent.vapi with correct command line order
ocagent_vapi = custom_target('ocagent-vapi',
  output: 'ocagent.vapi',
  input: ocagent_src,
  command: [
    valac_exe,
    '-C', '--debug',
    '--target-glib=auto',
    '--vapidir', meson.current_source_dir() / '../vapi',
    '--vapidir', meson.current_source_dir() / '../../vapi',
    '--vapidir', meson.current_build_dir(),
    '--pkg', 'posix',
    '--pkg', 'gee-0.8',
    '--pkg', 'gobject-2.0',
    '--pkg', 'glib-2.0',
    '--pkg', 'gio-2.0',
    '--pkg', 'json-glib-1.0',
    '--library', 'ocagent',
    '--header', meson.current_build_dir() / 'ocagent.h',  # Use header from library
    '--vapi', '@OUTPUT@',
    '@INPUT@'
  ],
  depends: [ocagent_base_lib],  # Ensure library is built first (so header exists)
  build_by_default: true,
  install: true,
  install_dir: get_option('datadir') / 'vala' / 'vapi'
)

# GObject Introspection for ocagent library
ocagent_gir = gnome.generate_gir(ocagent_base_lib,
  namespace: 'OLLMagent',
  nsversion: '1.0',
  identifier_prefix: 'OLLMagent',
  symbol_prefix: 'ollmagent',
  link_with: [],
  dependencies: [],
  extra_args: [
    '--accept-unprefixed'
  ],
  includes: ['GObject-2.0', 'Gio-2.0', 'Json-1.0'],
  install: true,
  fatal_warnings: false
)

# Create dependency for other libraries to use
ocagent_vapi_dep = declare_dependency(
  link_args: ['-L' + meson.current_build_dir(), '-locagent'],
  sources: [ocagent_vapi[0]]  # Include VAPI file to ensure it's built first
)


