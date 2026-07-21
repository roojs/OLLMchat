# oc-test-webkit — Phase 2 spike window for libocwebkit
# Extends TestAppBase (examples/TestAppBase.vala) like oc-test-gtkmd / oc-test-fetch.
# Don't use --pkg=ocwebkit when linking ocwebkit_base_lib — meson includes
# ocwebkit-meson.vapi automatically (same pattern as examples/oc-hf + ochf).

is_windows = host_machine.system() == 'windows'

oc_test_webkit_deps = [
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('json-glib-1.0'),
  dependency('gtk4'),
  dependency('libsoup-3.0'),
  ollmchat_vapi_dep,
]
oc_test_webkit_platform_vala = []
if is_windows
  oc_test_webkit_deps += dependency('webview2gtk-1')
  oc_test_webkit_platform_vala += ['--pkg=webview2gtk-1']
  if webview2gtk_prefix != ''
    oc_test_webkit_platform_vala += ['--vapidir', webview2gtk_prefix / 'lib']
  endif
else
  oc_test_webkit_deps += [
    dependency('webkitgtk-6.0'),
    dependency('atspi-2'),
  ]
  oc_test_webkit_platform_vala += [
    '--pkg=webkitgtk-6.0',
    '--pkg=atspi-2',
  ]
endif

oc_test_webkit_vala_args = [
  '--pkg=ollmchat',
  '--pkg=gtk4',
  '--pkg=libsoup-3.0',
  '--pkg=json-glib-1.0',
  '--pkg=ollamaweb',
  '--pkg=ocrpc',
  '--vapidir', meson.current_build_dir() / '../..' / 'libollmchat',
  '--vapidir', meson.current_build_dir() / '../..' / 'libocsqlite',
  '--vapidir', meson.current_build_dir() / '../..' / 'libocrpc',
  '--vapidir', meson.current_build_dir() / '../..' / 'libollamaweb',
] + oc_test_webkit_platform_vala
if not is_windows
  oc_test_webkit_vala_args += ['--vapidir', '/usr/share/vala/vapi']
endif

oc_test_webkit = executable('oc-test-webkit',
  sources: [
    meson.project_source_root() / 'examples' / 'TestAppBase.vala',
    'oc-test-webkit.vala',
  ],
  dependencies: oc_test_webkit_deps,
  link_with: [ollmchat_base_lib, ocwebkit_base_lib],
  build_rpath: ':'.join([
    meson.current_build_dir() / '..',
    meson.current_build_dir() / '../..' / 'libollmchat',
    meson.current_build_dir() / '../..' / 'libocsqlite',
    meson.current_build_dir() / '../..' / 'libocrpc',
    meson.current_build_dir() / '../..' / 'libollamaweb',
  ]),
  include_directories: [
    include_directories('../..' / 'libollmchat'),
    include_directories('..'),
  ],
  vala_args: oc_test_webkit_vala_args,
  install: false,
)
