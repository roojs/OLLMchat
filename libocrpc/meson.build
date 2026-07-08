# libocrpc — shared bin RPC wire types (OLLMrpc namespace)
#
# NOTE: Placeholder namespace.vala files (NamespaceDoc only) live in docs/meson.build
# valadoc input only — not here. See docs/code-documentation.md § Valadoc build.

valac = meson.get_compiler('vala')
is_windows = host_machine.system() == 'windows'
is_android = host_machine.system() == 'android'
use_unix_sockets = not is_windows and not is_android

ocrpc_deps = [
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('json-glib-1.0'),
  valac.find_library('posix'),
]

ocrpc_vapi_pkgs = [
  '--pkg=json-glib-1.0',
  '--pkg=posix',
]

ocrpc_vapi_gen_pkgs = [
  '--pkg', 'json-glib-1.0',
  '--pkg', 'posix',
  '--pkg', 'gio-2.0',
  '--pkg', 'gobject-2.0',
  '--pkg', 'glib-2.0',
  '--pkg', 'gee-0.8',
]

transport_socket_src = files(['windows/Transport/SocketListen.vala'])
client_boot_src = files(['windows/ClientBoot.vala'])

if use_unix_sockets
  ocrpc_deps += dependency('gio-unix-2.0')
  ocrpc_vapi_pkgs += '--pkg=gio-unix-2.0'
  ocrpc_vapi_gen_pkgs += [
    '--pkg', 'gio-unix-2.0',
  ]
  transport_socket_src = files(['Transport/SocketListen.vala'])
  client_boot_src = files(['ClientBoot.vala'])
endif

ocrpc_core_src = files([
  'namespace.vala',
  'Bin/Stream.vala',
  'Bin/Serializable.vala',
  'Bin/Json.vala',
  'Transport/Connection.vala',
  'Transport/Listen.vala',
  'Transport/TcpListen.vala',
  'CallParam.vala',
  'Daemon.vala',
  'Error.vala',
  'Notification.vala',
  'Request.vala',
  'Response.vala',
  'RpcErrorCode.vala',
])

ocrpc_src = ocrpc_core_src + files(['Client.vala']) + transport_socket_src + client_boot_src

ocrpc_base_lib = library('ocrpc',
  dependencies: ocrpc_deps,
  sources: ocrpc_src,
  vala_header: 'ocrpc.h',
  vala_vapi: 'ocrpc-meson.vapi',
  vala_args: [
    '--target-glib=auto',
  ] + ocrpc_vapi_pkgs + [
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
  ] + ocrpc_vapi_gen_pkgs + [
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
