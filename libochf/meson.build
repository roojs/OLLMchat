# libochf — Hugging Face Hub catalog (OLLMhf namespace)
#
# NOTE: If you add/remove/change source files here, update docs/meson.build valadoc
# input list (libochf section). See docs/code-documentation.md § Valadoc build.

valac = meson.get_compiler('vala')
is_android_cross = host_machine.system() == 'android'

ochf_deps = [
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('json-glib-1.0'),
  dependency('libsoup-3.0'),
  valac.find_library('posix'),
  ocrpc_vapi_dep,
]

ochf_src = files([
  'namespace.vala',
  'ModelFile.vala',
  'ModelHubTypes.vala',
  'Model.vala',
  'ModelArray.vala',
  'Param/Search.vala',
])

lib_build_rpath = ':'.join([
  meson.current_build_dir(),
  meson.current_build_dir() / '..' / 'libocrpc',
])

ochf_base_lib = library('ochf',
  dependencies: ochf_deps,
  sources: ochf_src,
  vala_header: 'ochf.h',
  vala_vapi: 'ochf-meson.vapi',
  build_rpath: lib_build_rpath,
  install: true,
)

ochf_vapi_cmd = [
  valac_exe,
  '-C', '--debug',
  '--target-glib=auto',
  '--vapidir', meson.current_source_dir() / '../vapi',
  '--vapidir', meson.current_build_dir(),
  '--vapidir', meson.current_build_dir() / '..' / 'libocrpc',
]
if is_android_cross
  ochf_vapi_cmd += ['--vapidir', gee_vapi_dir]
endif
ochf_vapi_cmd += [
  '--pkg', 'posix',
  '--pkg', 'libsoup-3.0',
  '--pkg', 'json-glib-1.0',
  '--pkg', 'gobject-2.0',
  '--pkg', 'glib-2.0',
  '--pkg', 'gio-2.0',
  '--pkg', 'gee-0.8',
  '--pkg', 'ocrpc',
  '--library', 'ochf',
  '--header', meson.current_build_dir() / 'ochf.h',
  '--vapi', '@OUTPUT@',
  '@INPUT@',
]
ochf_vapi = custom_target('ochf-vapi',
  output: 'ochf.vapi',
  input: ochf_src,
  command: ochf_vapi_cmd,
  depends: [ochf_base_lib],
  build_by_default: true,
  install: true,
  install_dir: get_option('datadir') / 'vala' / 'vapi',
)

ochf_vapi_dep = declare_dependency(
  link_args: ['-L' + meson.current_build_dir(), '-lochf'],
  sources: [ochf_vapi[0]],
)

ochf_vapi_only_dep = declare_dependency(
  sources: [ochf_vapi[0]],
)
