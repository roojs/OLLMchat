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
  dependency('libsoup-3.0'),
  valac.find_library('posix'),
  dependency('libffi'),
  dependency('gmodule-2.0'),
]

ocrpc_vapi_pkgs = [
  '--pkg=json-glib-1.0',
  '--pkg=libsoup-3.0',
  '--pkg=posix',
  '--pkg=libffi',
  '--pkg=gmodule-2.0',
]

ocrpc_vapi_gen_pkgs = [
  '--pkg', 'json-glib-1.0',
  '--pkg', 'libsoup-3.0',
  '--pkg', 'posix',
  '--pkg', 'libffi',
  '--pkg', 'gmodule-2.0',
  '--pkg', 'gio-2.0',
  '--pkg', 'gobject-2.0',
  '--pkg', 'glib-2.0',
  '--pkg', 'gee-0.8',
]

transport_socket_src = files(['windows/Transport/SocketListen.vala'])
client_boot_src = files(['windows/ClientBoot.vala'])
gi_src = files(['windows/Gi.vala'])

if use_unix_sockets
  ocrpc_deps += dependency('gio-unix-2.0')
  ocrpc_vapi_pkgs += '--pkg=gio-unix-2.0'
  ocrpc_vapi_gen_pkgs += [
    '--pkg', 'gio-unix-2.0',
  ]
  ocrpc_deps += dependency('gobject-introspection-1.0')
  ocrpc_vapi_pkgs += '--pkg=gobject-introspection-1.0'
  ocrpc_vapi_gen_pkgs += [
    '--pkg', 'gobject-introspection-1.0',
  ]
  transport_socket_src = files(['Transport/SocketListen.vala'])
  client_boot_src = files(['ClientBoot.vala'])
  gi_src = files(['Gi.vala'])
endif

if is_android
  ocrpc_vapi_pkgs += '--define=ANDROID'
  ocrpc_vapi_gen_pkgs += ['--define', 'ANDROID']
endif
if is_windows
  ocrpc_vapi_pkgs += '--define=G_OS_WIN32'
  ocrpc_vapi_gen_pkgs += ['--define', 'G_OS_WIN32']
endif

ocrpc_core_src = files([
  'namespace.vala',
  'Bin/namespace.vala',
  'Bin/Stream.vala',
  'Bin/StreamValue.vala',
  'Bin/Serializable.vala',
  'Bin/Json.vala',
  'Transport/Connection.vala',
  'Transport/Listen.vala',
  'Transport/TcpListen.vala',
  'Daemon.vala',
  'Error.vala',
  'Notification.vala',
  'Request.vala',
  'Ffi.vala',
  'Response.vala',
  'RpcErrorCode.vala',
])

live_src = files([
  'Live/namespace.vala',
  'Live/Handle.vala',
])
if use_unix_sockets
  live_src += files([
    'Live/Buffer.vala',
    'Live/BufferStream.vala',
    'Live/BufferListen.vala',
    'Live/Remote.vala',
    'Live/Subscription.vala',
    'Live/Subscribe.vala',
    'Live/Callback.vala',
    'Live/Hook.vala',
    'Live/Invoke.vala',
  ])
endif

ocrpc_core_src += live_src
ocrpc_core_src += gi_src

ocrpc_src = ocrpc_core_src + files(['Client.vala']) + transport_socket_src + client_boot_src

ocrpc_base_lib = library('ocrpc',
  dependencies: ocrpc_deps,
  sources: ocrpc_src,
  include_directories: include_directories('.'),
  vala_header: 'ocrpc.h',
  vala_vapi: 'ocrpc-meson.vapi',
  vala_args: [
    '--target-glib=auto',
  ] + ocrpc_vapi_pkgs + [
    '--vapidir', meson.current_source_dir(),
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
    '--vapidir', meson.current_source_dir(),
    '--vapidir', '/usr/share/vala/vapi',
  ] + (is_android ? ['--vapidir', gee_vapi_dir] : []) + ocrpc_vapi_gen_pkgs + [
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
