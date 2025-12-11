# Build occoder library (liboccoder.so) - depends on libocsqlite

# Dependencies for occoder library
valac = meson.get_compiler('vala')
occoder_deps = [
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('sqlite3'),
  valac.find_library('posix'),
]

occoder_src = files([
  'files/FileBase.vala',
  'files/File.vala',
  'files/Folder.vala',
  'files/Project.vala',
  'ProjectManager.vala',
])

# Build rpath for libraries to find each other in build directory
lib_build_rpath = ':'.join([
  meson.current_build_dir(),
  meson.current_build_dir() / '..' / 'libocsqlite',
  meson.current_build_dir() / '..' / 'libocmarkdown',
  meson.current_build_dir() / '..' / 'libocmarkdowngtk',
  meson.current_build_dir() / '..' / 'libollmchat',
  meson.current_build_dir() / '..' / 'libollmchatgtk'
])

occoder_base_lib = library('occoder',
  dependencies: [occoder_deps, ocsqlite_vapi_dep],
  sources: occoder_src,
  vala_header: 'occoder.h',
  vala_vapi: 'occoder.vapi',
  build_rpath: lib_build_rpath,
  vala_args: ['--pkg=sqlite3', '--pkg=ocsqlite', '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite'],
  install: true
)

# GObject Introspection for occoder library
occoder_gir = gnome.generate_gir(occoder_base_lib,
  namespace: 'OLLMcoder',
  nsversion: '1.0',
  identifier_prefix: 'OLLMcoder',
  symbol_prefix: 'ollmcoder',
  link_with: [ocsqlite_base_lib],
  dependencies: [dependency('sqlite3')],
  extra_args: [
    '--extra-library=ocsqlite',
    '--accept-unprefixed'
  ],
  includes: ['GObject-2.0', 'Gio-2.0', ocsqlite_gir[0]],
  install: true,
  fatal_warnings: false
)

# Create dependency for other libraries to use
occoder_vapi_dep = declare_dependency(
  link_with: occoder_base_lib,
  sources: occoder_base_lib.get_variable('vala_vapi', []),
  dependencies: [ocsqlite_vapi_dep]
)
