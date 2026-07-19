# libocwebkit — OLLMwebkit browser tool (WebKitGTK + OLLMchat.Tool)
#
# NOTE: If you add/remove/change source files here, update docs/meson.build
# valadoc input list (libocwebkit section). See docs/code-documentation.md.

valac = meson.get_compiler('vala')
is_android_cross = host_machine.system() == 'android'

ocwebkit_deps = [
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('json-glib-1.0'),
  dependency('gtk4'),
  dependency('webkitgtk-6.0'),
  dependency('libsoup-3.0'),
  dependency('atspi-2'),
  valac.find_library('posix'),
]

glib_compile_resources = find_program('glib-compile-resources', native: true)
ocwebkit_resources_c = custom_target(
  'ocwebkit-resources_c',
  input: 'gresources.xml',
  output: 'ocwebkit-resources.c',
  command: [
    glib_compile_resources,
    '@INPUT@',
    '--sourcedir', meson.current_source_dir() / 'resources',
    '--c-name', 'ocwebkit_resources',
    '--internal',
    '--generate-source',
    '--target', '@OUTPUT@',
    '--dependency-file', '@DEPFILE@',
  ],
  depfile: 'ocwebkit-resources.c.d',
)

ocwebkit_resources_h = custom_target(
  'ocwebkit-resources_h',
  input: 'gresources.xml',
  output: 'ocwebkit-resources.h',
  command: [
    glib_compile_resources,
    '@INPUT@',
    '--sourcedir', meson.current_source_dir() / 'resources',
    '--c-name', 'ocwebkit_resources',
    '--internal',
    '--generate-header',
    '--target', '@OUTPUT@',
  ],
)

ocwebkit_resources = [ocwebkit_resources_c, ocwebkit_resources_h]

ocwebkit_src = files([
  'namespace.vala',
  'A11y.vala',
  'A11yParse.vala',
  'Browser.vala',
  'BrowserStack.vala',
  'Cloudflare.vala',
  'Request.vala',
  'Tool.vala',
])

lib_build_rpath = ':'.join([
  meson.current_build_dir(),
  meson.current_build_dir() / '..' / 'libollmchat',
  meson.current_build_dir() / '..' / 'libocsqlite',
  meson.current_build_dir() / '..' / 'libocrpc',
  meson.current_build_dir() / '..' / 'libollamaweb',
])

ocwebkit_lib_deps = [ocwebkit_deps, ollmchat_vapi_dep]

ocwebkit_base_lib = library('ocwebkit',
  dependencies: ocwebkit_lib_deps,
  link_with: [ollmchat_base_lib],
  sources: [ocwebkit_src, ocwebkit_resources],
  vala_header: 'ocwebkit.h',
  vala_vapi: 'ocwebkit-meson.vapi',
  build_rpath: lib_build_rpath,
  include_directories: [
    include_directories('..' / 'libollmchat'),
  ],
  vala_args: [
    '-D', 'LINUX',
    '--pkg=ollmchat',
    '--pkg=gtk4',
    '--pkg=webkitgtk-6.0',
    '--pkg=libsoup-3.0',
    '--pkg=atspi-2',
    '--pkg=json-glib-1.0',
    '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libocrpc',
    '--vapidir', meson.current_build_dir() / '..' / 'libollamaweb',
    '--vapidir', '/usr/share/vala/vapi',
  ],
  install: true,
)

ocwebkit_vapi_cmd = [
  valac_exe,
  '-C', '--debug',
  '--target-glib=auto',
  '--vapidir', meson.current_source_dir() / '../vapi',
  '--vapidir', meson.current_build_dir(),
  '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
  '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
  '--vapidir', meson.current_build_dir() / '..' / 'libocrpc',
  '--vapidir', meson.current_build_dir() / '..' / 'libollamaweb',
  '--vapidir', '/usr/share/vala/vapi',
]
if is_android_cross
  ocwebkit_vapi_cmd += ['--vapidir', gee_vapi_dir]
endif
ocwebkit_vapi_cmd += [
  '-D', 'LINUX',
  '--pkg', 'posix',
  '--pkg', 'json-glib-1.0',
  '--pkg', 'gobject-2.0',
  '--pkg', 'glib-2.0',
  '--pkg', 'gio-2.0',
  '--pkg', 'gee-0.8',
  '--pkg', 'gtk4',
  '--pkg', 'webkitgtk-6.0',
  '--pkg', 'libsoup-3.0',
  '--pkg', 'atspi-2',
  '--pkg', 'sqlite3',
  '--pkg', 'ocrpc',
  '--pkg', 'ocsqlite',
  '--pkg', 'ollamaweb',
  '--pkg', 'ollmchat',
  '--library', 'ocwebkit',
  '--header', meson.current_build_dir() / 'ocwebkit.h',
  '--vapi', '@OUTPUT@',
  '@INPUT@',
]

ocwebkit_vapi = custom_target('ocwebkit-vapi',
  output: 'ocwebkit.vapi',
  input: ocwebkit_src,
  command: ocwebkit_vapi_cmd,
  depends: [ocwebkit_base_lib],
  build_by_default: true,
  install: true,
  install_dir: get_option('datadir') / 'vala' / 'vapi',
)

ocwebkit_vapi_dep = declare_dependency(
  link_args: ['-L' + meson.current_build_dir(), '-locwebkit'],
  sources: [ocwebkit_vapi[0]],
)

subdir('examples')
