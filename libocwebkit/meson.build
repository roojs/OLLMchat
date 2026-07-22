# libocwebkit — OLLMwebkit browser tool (WebKitGTK / webview2-gtk + OLLMchat.Tool)
#
# NOTE: If you add/remove/change source files here, update docs/meson.build
# valadoc input list (libocwebkit section). See docs/code-documentation.md.

valac = meson.get_compiler('vala')
is_android_cross = host_machine.system() == 'android'
is_windows = host_machine.system() == 'windows'

ocwebkit_deps = [
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('json-glib-1.0'),
  dependency('gtk4'),
  dependency('libsoup-3.0'),
  valac.find_library('posix'),
]

ocwebkit_platform_vala_args = []
ocwebkit_vapi_platform_pkgs = []
if is_windows
  ocwebkit_deps += dependency('webview2gtk-1')
  ocwebkit_platform_vala_args += ['--pkg=webview2gtk-1']
  ocwebkit_vapi_platform_pkgs += ['--pkg', 'webview2gtk-1']
  if webview2gtk_prefix != ''
    ocwebkit_platform_vala_args += ['--vapidir', webview2gtk_prefix / 'lib']
    ocwebkit_vapi_platform_pkgs += ['--vapidir', webview2gtk_prefix / 'lib']
  endif
elif is_android_cross
  # Subproject library already injects its generated .vapi into valac inputs
  # for the shared library. Do not also pass --pkg=webkitgtk-android-1 there
  # (duplicate definitions). The ocwebkit.vapi custom_target does not get that
  # injection, so it still needs --pkg + --vapidir.
  ocwebkit_deps += dependency('webkitgtk-android-1')
  ocwebkit_vapi_platform_pkgs += [
    '--pkg', 'webkitgtk-android-1',
    '--vapidir', meson.current_build_dir() / '..' / 'subprojects' / 'webkitgtk-android',
  ]
else
  ocwebkit_deps += [
    dependency('webkitgtk-6.0'),
    dependency('atspi-2'),
  ]
  ocwebkit_platform_vala_args += [
    '--pkg=webkitgtk-6.0',
    '--pkg=atspi-2',
  ]
  ocwebkit_vapi_platform_pkgs += [
    '--pkg', 'webkitgtk-6.0',
    '--pkg', 'atspi-2',
  ]
endif

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

ocwebkit_vala_args = [
  '--pkg=ollmchat',
  '--pkg=gtk4',
  '--pkg=libsoup-3.0',
  '--pkg=json-glib-1.0',
  '--pkg=sqlite3',
  '--pkg=ocsqlite',
  '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
  '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
  '--vapidir', meson.current_build_dir() / '..' / 'libocrpc',
  '--vapidir', meson.current_build_dir() / '..' / 'libollamaweb',
] + ocwebkit_platform_vala_args
if not is_windows
  ocwebkit_vala_args += ['--vapidir', '/usr/share/vala/vapi']
endif

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
  vala_args: ocwebkit_vala_args,
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
]
if not is_windows
  ocwebkit_vapi_cmd += ['--vapidir', '/usr/share/vala/vapi']
endif
if is_android_cross
  ocwebkit_vapi_cmd += ['--vapidir', gee_vapi_dir]
  # custom_target does not inherit add_project_arguments --define=ANDROID
  ocwebkit_vapi_cmd += ['--define=ANDROID']
endif
ocwebkit_vapi_cmd += [
  '--pkg', 'posix',
  '--pkg', 'json-glib-1.0',
  '--pkg', 'gobject-2.0',
  '--pkg', 'glib-2.0',
  '--pkg', 'gio-2.0',
  '--pkg', 'gee-0.8',
  '--pkg', 'gtk4',
  '--pkg', 'libsoup-3.0',
  '--pkg', 'sqlite3',
  '--pkg', 'ocrpc',
  '--pkg', 'ocsqlite',
  '--pkg', 'ollamaweb',
  '--pkg', 'ollmchat',
] + ocwebkit_vapi_platform_pkgs + [
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

if not is_android_cross
  subdir('examples')
endif
