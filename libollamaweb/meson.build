# libollamaweb — Ollama.com search/tags HTML parsing (no libollmchat dependency)

valac = meson.get_compiler('vala')

ollamaweb_deps = [
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('json-glib-1.0'),
  dependency('libsoup-3.0'),
  dependency('libxml-2.0'),
  valac.find_library('posix'),
]

ollamaweb_src = files([
  'ModelVariant.vala',
  'Model.vala',
  'Search/Category.vala',
  'Search/Parser.vala',
  'Search/Client.vala',
  'Search/Service.vala',
  'Search/Cache.vala',
  'Search/Session.vala',
])

lib_build_rpath = ':'.join([
  meson.current_build_dir(),
])

ollamaweb_base_lib = library('ollamaweb',
  dependencies: ollamaweb_deps,
  sources: ollamaweb_src,
  vala_header: 'ollamaweb.h',
  vala_vapi: 'ollamaweb-meson.vapi',
  build_rpath: lib_build_rpath,
  install: true
)

ollamaweb_vapi = custom_target('ollamaweb-vapi',
  output: 'ollamaweb.vapi',
  input: ollamaweb_src,
  command: [
    valac_exe,
    '-C', '--debug',
    '--target-glib=auto',
    '--vapidir', meson.current_source_dir() / '../vapi',
    '--vapidir', meson.current_build_dir(),
    '--pkg', 'posix',
    '--pkg', 'libxml-2.0',
    '--pkg', 'libsoup-3.0',
    '--pkg', 'json-glib-1.0',
    '--pkg', 'gobject-2.0',
    '--pkg', 'glib-2.0',
    '--pkg', 'gio-2.0',
    '--pkg', 'gee-0.8',
    '--library', 'ollamaweb',
    '--header', meson.current_build_dir() / 'ollamaweb.h',
    '--vapi', '@OUTPUT@',
    '@INPUT@'
  ],
  depends: [ollamaweb_base_lib],
  build_by_default: true,
  install: true,
  install_dir: get_option('datadir') / 'vala' / 'vapi'
)

ollamaweb_vapi_dep = declare_dependency(
  link_args: ['-L' + meson.current_build_dir(), '-lollamaweb'],
  sources: [ollamaweb_vapi[0]]
)

ollamaweb_vapi_only_dep = declare_dependency(
  sources: [ollamaweb_vapi[0]]
)
