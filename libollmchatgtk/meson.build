# Build GTK library (libollmchatgtk.so) - depends on base library and ocmarkdown libraries
# Depends on libollmchat, libocmarkdown, libocmarkdowngtk, libocsqlite
#
# NOTE: If you add/remove/change source files in this directory, you MUST also
# update docs/meson.build to include the same files in the valadoc input list.

# Dependencies for ollmchatgtk library
valac = meson.get_compiler('vala')
ollmchatgtk_deps = [
  dependency('gtk4'),
  dependency('libadwaita-1'),
  dependency('gtksourceview-5'),
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('json-glib-1.0'),
  dependency('libsoup-3.0'),
  valac.find_library('posix'),
]

# GTK source files (for GTK library and test-window)
ollmchatgtk_src = files([
  'ChatWidget.vala',
  'ChatView.vala',
  'ChatInput.vala',
  'ChatBar.vala',
  'ChatPermission.vala',
  # TODO: Clipboard feature needs proper design - see TODO.md
  # 'ClipboardManager.vala',
  # 'ClipboardMetadata.vala',
  'HistoryBrowser.vala',
  'Tools/Permission.vala',
  'List/ModelUsageFilter.vala',
  'List/ModelUsageSort.vala',
  'List/ModelUsageFactory.vala',
  'List/SortedList.vala',
])

# Build rpath for libraries to find each other in build directory
lib_build_rpath = ':'.join([
  meson.current_build_dir(),
  meson.current_build_dir() / '..' / 'libocsqlite',
  meson.current_build_dir() / '..' / 'libocmarkdown',
  meson.current_build_dir() / '..' / 'libocmarkdowngtk',
  meson.current_build_dir() / '..' / 'libollmchat',
  meson.current_build_dir() / '..' / 'libollamaweb'
])

ollmchatgtk_lib = library('ollmchatgtk',
  dependencies: [ollmchatgtk_deps],
  sources: [ollmchatgtk_src],
  vala_header: 'ollmchatgtk.h',
  vala_vapi: 'ollmchatgtk.vapi',
  vala_gir: 'OLLMchatGtk-1.0.gir',
  link_with: [ollmchat_base_lib, ocmarkdown_base_lib, ocmarkdowngtk_lib],  # Link with base libraries
  include_directories: [
    include_directories('../libollmchat'),
    include_directories('../libollamaweb'),
    include_directories('../libocmarkdown'),
    include_directories('../libocmarkdowngtk'),
    include_directories('../libocsqlite')
  ],
  build_rpath: lib_build_rpath,
  # When using link_with, meson auto-includes the meson-generated VAPIs from linked libraries
  # We only need --pkg for ocsqlite since ollmchat_base_lib doesn't link_with it (uses link_args instead)
  vala_args: [
    '--pkg=sqlite3',
    '--pkg=ocsqlite',
    '--pkg=ollamaweb',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libollamaweb',
    '--girdir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--girdir', meson.current_build_dir() / '..' / 'libocmarkdown',
    '--girdir', meson.current_build_dir() / '..' / 'libocmarkdowngtk',
    '--girdir', meson.current_build_dir() / '..' / 'libollmchat',
  ],
  install: true
)

ollmchatgtk_gir_file = meson.current_build_dir() / 'OLLMchatGtk-1.0.gir'
ollmchatgtk_gir_fixed = meson.current_build_dir() / 'OLLMchatGtk-1.0.fixed.gir'
compile_ollmchatgtk_typelib = find_program('compile-typelib.sh', dirs: meson.current_source_dir())
custom_target('ollmchatgtk-typelib',
  output: 'OLLMchatGtk-1.0.typelib',
  command: [
    compile_ollmchatgtk_typelib,
    ollmchatgtk_gir_file,
    ollmchatgtk_gir_fixed,
    '@OUTPUT@',
    '--includedir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--includedir', meson.current_build_dir() / '..' / 'libocmarkdown',
    '--includedir', meson.current_build_dir() / '..' / 'libocmarkdowngtk',
    '--includedir', meson.current_build_dir() / '..' / 'libollmchat',
    '--includedir', '/usr/share/gir-1.0',
  ],
  depends: ollmchatgtk_lib,
  build_by_default: true,
  install: true,
  install_dir: get_option('libdir') / 'girepository-1.0',
)
meson.add_install_script(
  'sh', '-c',
  'install -Dm644 "' + ollmchatgtk_gir_file + '" "$DESTDIR$MESON_INSTALL_PREFIX/share/gir-1.0/OLLMchatGtk-1.0.gir"',
)
