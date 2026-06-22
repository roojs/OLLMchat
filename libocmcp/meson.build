# Build ocmcp library (libocmcp.so) - depends on libollmchat, libocfiles, libocbwrap
#
# NOTE: If you add/remove/change source files here, update docs/meson.build valadoc
# input list. libocbwrap sources must appear before libocmcp in that list.

valac = meson.get_compiler('vala')

ocmcp_deps = [
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('gmodule-2.0'),
  dependency('json-glib-1.0'),
  dependency('libsoup-3.0'),
  valac.find_library('posix'),
]

ocmcp_src = files([
  'McpTypes.vala',
  'Config.vala',
  'Client/Base.vala',
  'Client/Stdio.vala',
  'Client/Http.vala',
  'Factory.vala',
  'Tool.vala',
  'Request.vala',
  'Loader.vala',
  'Registry.vala',
])

lib_build_rpath = ':'.join([
  meson.current_build_dir(),
  meson.current_build_dir() / '..' / 'libocfiles',
  meson.current_build_dir() / '..' / 'libollmchat',
  meson.current_build_dir() / '..' / 'libollamaweb',
  meson.current_build_dir() / '..' / 'libocbwrap',
])

ocmcp_base_lib = library('ocmcp',
  dependencies: [
    ocmcp_deps,
    ollmchat_vapi_dep,
    ocfiles_vapi_dep,
    ocbwrap_vapi_dep,
  ],
  sources: ocmcp_src,
  link_with: [ollmchat_base_lib],
  vala_header: 'ocmcp.h',
  vala_vapi: 'ocmcp-meson.vapi',
  build_rpath: lib_build_rpath,
  include_directories: [
    include_directories('..' / 'libollmchat'),
    include_directories('..' / 'libollamaweb'),
  ],
  vala_args: [
    '--pkg=ollmchat',
    '--pkg=ollamaweb',
    '--pkg=ocfiles',
    '--pkg=ocbwrap',
    '--pkg=gmodule-2.0',
    '--pkg=tree-sitter',
    '--pkg=json-glib-1.0',
    '--pkg=libsoup-3.0',
    '--vapidir', meson.current_build_dir() / '..' / 'libocfiles',
    '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
    '--vapidir', meson.current_build_dir() / '..' / 'libollamaweb',
    '--vapidir', meson.current_build_dir() / '..' / 'libocbwrap',
    '--vapidir', meson.current_source_dir() / '../vapi',
  ],
  install: true
)

ocmcp_vapi = custom_target('ocmcp-vapi',
  output: 'ocmcp.vapi',
  input: ocmcp_src,
  command: [
    valac_exe,
    '-C', '--debug',
    '--target-glib=auto',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libocfiles',
    '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
    '--vapidir', meson.current_build_dir() / '..' / 'libollamaweb',
    '--vapidir', meson.current_build_dir() / '..' / 'libocbwrap',
    '--vapidir', meson.current_source_dir() / '../vapi',
    '--vapidir', '/usr/share/vala/vapi',
    '--pkg', 'posix',
    '--pkg', 'sqlite3',
    '--pkg', 'json-glib-1.0',
    '--pkg', 'libsoup-3.0',
    '--pkg', 'ocsqlite',
    '--pkg', 'ollmchat',
    '--pkg', 'ollamaweb',
    '--pkg', 'ocfiles',
    '--pkg', 'ocbwrap',
    '--pkg', 'gmodule-2.0',
    '--pkg', 'tree-sitter',
    '--pkg', 'gobject-2.0',
    '--pkg', 'glib-2.0',
    '--pkg', 'gio-2.0',
    '--pkg', 'gee-0.8',
    '--library', 'ocmcp',
    '--header', meson.current_build_dir() / 'ocmcp.h',
    '--vapi', '@OUTPUT@',
    '@INPUT@'
  ],
  depends: [ocmcp_base_lib, ollamaweb_vapi, ocbwrap_vapi],
  build_by_default: true,
  install: true,
  install_dir: get_option('datadir') / 'vala' / 'vapi'
)

ocmcp_vapi_dep = declare_dependency(
  link_args: ['-L' + meson.current_build_dir(), '-locmcp'],
  sources: [ocmcp_vapi[0]],
  dependencies: [ollmchat_vapi_dep, ocfiles_vapi_dep, ocbwrap_vapi_dep]
)
