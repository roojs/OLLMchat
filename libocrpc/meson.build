# libocrpc — shared JSON-RPC wire types (OLLMrpc namespace)

valac = meson.get_compiler('vala')

ocrpc_deps = [
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('gio-unix-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('json-glib-1.0'),
  valac.find_library('posix'),
]

ocrpc_src = files([
  'namespace.vala',
  'Transport/namespace.vala',
  'Transport/Connection.vala',
  'Transport/Listen.vala',
  'Transport/SocketListen.vala',
  'CallParam.vala',
  'Error.vala',
  'Notification.vala',
  'Request.vala',
  'Response.vala',
  'RpcErrorCode.vala',
  'ClientBoot.vala',
  'Client.vala',
])

ocrpc_base_lib = library('ocrpc',
  dependencies: ocrpc_deps,
  sources: ocrpc_src,
  vala_header: 'ocrpc.h',
  vala_vapi: 'ocrpc-meson.vapi',
  vala_args: [
    '--target-glib=auto',
    '--pkg=json-glib-1.0',
    '--pkg=posix',
    '--vapidir', '/usr/share/vala/vapi',
  ],
  install: true,
)

ocrpc_vapi = custom_target('ocrpc-vapi',
  output: 'ocrpc.vapi',
  input: ocrpc_src,
  command: [
    valac_exe,
    '-C', '--debug',
    '--target-glib=auto',
    '--vapidir', meson.current_build_dir(),
    '--vapidir', '/usr/share/vala/vapi',
    '--pkg', 'json-glib-1.0',
    '--pkg', 'posix',
    '--pkg', 'gio-unix-2.0',
    '--pkg', 'gio-2.0',
    '--pkg', 'gobject-2.0',
    '--pkg', 'glib-2.0',
    '--pkg', 'gee-0.8',
    '--library', 'ocrpc',
    '--header', meson.current_build_dir() / 'ocrpc.h',
    '--vapi', '@OUTPUT@',
    '@INPUT@',
  ],
  depends: [ocrpc_base_lib],
  build_by_default: true,
  install: true,
  install_dir: get_option('datadir') / 'vala' / 'vapi',
)

ocrpc_vapi_dep = declare_dependency(
  link_args: ['-L' + meson.current_build_dir(), '-locrpc'],
  sources: [ocrpc_vapi[0]],
)
