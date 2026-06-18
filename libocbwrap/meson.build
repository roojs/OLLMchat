# libocbwrap — shared bwrap / overlay / seccomp / Scan (OLLMbwrap namespace)
# Linux desktop only. No libocfiles dependency.
#
# Windows / Android: library not built. Callers use compile-time guards
# (#if G_OS_LINUX) or existing can_wrap() false paths — see plan step 4.

if host_machine.system() != 'linux'
  ocbwrap_vapi_dep = disabler()
  subdir_done()
endif

valac = meson.get_compiler('vala')

ocbwrap_deps = [
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  valac.find_library('posix'),
  dependency('gio-unix-2.0'),
  valac.find_library('linux'),
]

seccomp_vapi = valac.find_library(
  'seccomp',
  dirs: meson.current_source_dir() / '../vapi',
  required: true,
)
ocbwrap_deps += [
  seccomp_vapi,
  libseccomp_dep,
]

ocbwrap_vapi_pkgs = [
  '--pkg=posix',
  '--pkg=seccomp',
  '--pkg=linux',
  '--pkg=gio-unix-2.0',
]

ocbwrap_vapi_gen_pkgs = [
  '--pkg', 'posix',
  '--pkg', 'seccomp',
  '--pkg', 'linux',
  '--pkg', 'gio-unix-2.0',
  '--pkg', 'gobject-2.0',
  '--pkg', 'glib-2.0',
  '--pkg', 'gio-2.0',
  '--pkg', 'gee-0.8',
]

ocbwrap_extra_sources = files(meson.current_source_dir() / '../vapi/seccomp-fd-pass.c')

ocbwrap_src = files([
  'namespace.vala',
  'FileVerification.vala',
  'Bubble.vala',
  'Overlay.vala',
  'RunSeccomp.vala',
  'Scan.vala',
])

lib_build_rpath = ':'.join([
  meson.current_build_dir(),
])

ocbwrap_base_lib = library('ocbwrap',
  dependencies: ocbwrap_deps,
  sources: ocbwrap_src + ocbwrap_extra_sources,
  vala_header: 'ocbwrap.h',
  vala_vapi: 'ocbwrap-meson.vapi',
  vala_gir: 'OLLMbwrap-1.0.gir',
  build_rpath: lib_build_rpath,
  include_directories: [
    include_directories('..' / 'vapi'),
  ],
  vala_args: ocbwrap_vapi_pkgs + strcasestr_vala_args + [
    '--vapidir', meson.current_source_dir() / '../vapi',
    '--vapidir', '/usr/share/vala/vapi',
  ],
  install: true,
)

ocbwrap_vapi = custom_target('ocbwrap-vapi',
  output: 'ocbwrap.vapi',
  input: ocbwrap_src,
  command: [
    valac_exe,
    '-C', '--debug',
    '--target-glib=auto',
    '--vapidir', meson.current_build_dir(),
    '--vapidir', meson.current_source_dir() / '../vapi',
    '--vapidir', '/usr/share/vala/vapi',
  ] + ocbwrap_vapi_gen_pkgs + strcasestr_vala_args + [
    '--library', 'ocbwrap',
    '--header', meson.current_build_dir() / 'ocbwrap.h',
    '--vapi', '@OUTPUT@',
    '@INPUT@',
  ],
  depends: [ocbwrap_base_lib],
  build_by_default: true,
  install: true,
  install_dir: get_option('datadir') / 'vala' / 'vapi',
)

ocbwrap_vapi_dep = declare_dependency(
  link_args: ['-L' + meson.current_build_dir(), '-locbwrap'],
  sources: [ocbwrap_vapi[0]],
  dependencies: ocbwrap_deps,
)

ocbwrap_gir_file = meson.current_build_dir() / 'OLLMbwrap-1.0.gir'
custom_target('ocbwrap-typelib',
  output: 'OLLMbwrap-1.0.typelib',
  command: [
    g_ir_compiler, ocbwrap_gir_file, '--output', '@OUTPUT@',
    '--includedir', '/usr/share/gir-1.0',
  ],
  depends: ocbwrap_base_lib,
  build_by_default: true,
  install: true,
  install_dir: get_option('libdir') / 'girepository-1.0',
)
meson.add_install_script(
  'sh', '-c',
  'install -Dm644 "' + ocbwrap_gir_file + '" "$DESTDIR$MESON_INSTALL_PREFIX/share/gir-1.0/OLLMbwrap-1.0.gir"',
)
