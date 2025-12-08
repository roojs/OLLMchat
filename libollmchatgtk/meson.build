# Build GTK library (libollmchatgtk.so) - depends on base library and ocmarkdown libraries
# Depends on libollmchat, libocmarkdown, libocmarkdowngtk, libocsqlite

# Dependencies for ollmchatgtk library
valac = meson.get_compiler('vala')
ollmchatgtk_deps = [
  dependency('gtk4'),
  dependency('gtksourceview-5'),
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('json-glib-1.0'),
  dependency('libsoup-3.0'),
  valac.find_library('posix'),
]

# Source files for Tools namespace (GTK-dependent)
ollmchat_tools_gtk_src = files([
  'Tools/RunCommand.vala',
  'Tools/RequestRunCommand.vala',
  'Tools/Permission.vala',
])

# GTK source files (for GTK library and test-window)
ollmchatgtk_src = files([
  'ChatWidget.vala',
  'ChatView.vala',
  'ChatInput.vala',
  'ChatPermission.vala',
  'HistoryBrowser.vala',
  'Message.vala',
]) + ollmchat_tools_gtk_src

# Build rpath for libraries to find each other in build directory
lib_build_rpath = ':'.join([
  meson.current_build_dir(),
  meson.current_build_dir() / '..' / 'libocsqlite',
  meson.current_build_dir() / '..' / 'libocmarkdown',
  meson.current_build_dir() / '..' / 'libocmarkdowngtk',
  meson.current_build_dir() / '..' / 'libollmchat'
])

ollmchatgtk_lib = library('ollmchatgtk',
  dependencies: ollmchatgtk_deps,
  sources: [ollmchat_tools_gtk_src, ollmchatgtk_src],
  vala_header: 'ollmchatgtk.h',
  vala_vapi: 'ollmchatgtk.vapi',
  link_with: [ollmchat_base_lib, ocmarkdown_base_lib, ocmarkdowngtk_lib],  # Link with base libraries
  include_directories: [
    include_directories('../libollmchat'),
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
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite'
  ],
  install: true
)

# GObject Introspection for GTK library
# Identifier prefix is 'OLLMchat' because the GTK library contains symbols from
# multiple namespaces (OLLMchatGtk, OLLMchatGtk.Tools) that all start with 'OLLMchat'
# We include the base library GIR so the GTK library can reference base types
# For Vala libraries, meson doesn't automatically populate the filelist with the header.
# We need to pass the header file explicitly in the 'sources' parameter.
# The header file is generated in the build directory by the Vala compiler.
ollmchatgtk_header_file = meson.current_build_dir() / 'ollmchatgtk.h'

ollmchatgtk_gir = gnome.generate_gir(ollmchatgtk_lib,
  namespace: 'OLLMchatGtk',
  nsversion: '1.0',
  identifier_prefix: 'OLLMchat',
  symbol_prefix: 'ollmchat',
  sources: [ollmchatgtk_header_file],
  link_with: [ollmchat_base_lib, ocmarkdown_base_lib, ocmarkdowngtk_lib, ocsqlite_base_lib],
  dependencies: [dependency('sqlite3')],
  extra_args: [
    '--extra-library=ollmchat',
    '--extra-library=ocmarkdown',
    '--extra-library=ocmarkdowngtk',
    '--extra-library=ocsqlite',
    '--accept-unprefixed'
  ],
  includes: ['GObject-2.0', 'Gio-2.0', 'Gtk-4.0', 'GtkSource-5', 'Gee-0.8', ollmchat_gir[0], ocmarkdown_gir[0], ocmarkdowngtk_gir[0], ocsqlite_gir[0]],
  install: true,
  fatal_warnings: false
)
