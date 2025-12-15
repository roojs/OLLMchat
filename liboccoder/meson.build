# Build occoder library (liboccoder.so) - depends on libocsqlite

# Dependencies for occoder library
valac = meson.get_compiler('vala')
occoder_deps = [
  dependency('gtk4'),
  dependency('gtksourceview-5'),
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('json-glib-1.0'),
  dependency('sqlite3'),
  valac.find_library('posix'),
]

occoder_src = files([
  'files/FileBase.vala',
  'files/File.vala',
  'files/FileAlias.vala',
  'files/Folder.vala',
  'files/FolderFiles.vala',
  'files/ProjectFile.vala',
  'files/ProjectFiles.vala',
  'ProjectManager.vala',
  'ProjectMigrate.vala',
  'SearchableDropdown.vala',
  'ProjectDropdown.vala',
  'FileDropdown.vala',
  'SourceView.vala',
  'Diff/Patch.vala',
  'Diff/PatchCreator.vala',
  'Diff/PatchApplier.vala',
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
  vala_vapi: 'occoder-meson.vapi',  # Use different name so our custom_target can use 'occoder.vapi'
  build_rpath: lib_build_rpath,
  vala_args: [
    '--pkg=sqlite3',
    '--pkg=ocsqlite',
    '--pkg=json-glib-1.0',
    '--pkg=gtk4',
    '--pkg=gtksourceview-5',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite'
  ],
  install: true
)

# Manually generate occoder.vapi with correct command line order
occoder_vapi = custom_target('occoder-vapi',
  output: 'occoder.vapi',
  input: occoder_src,
  command: [
    valac_exe,
    '-C', '--debug',
    '--target-glib=auto',
    '--vapidir', meson.current_source_dir() / '../vapi',
    '--vapidir', meson.current_source_dir() / '../../vapi',
    '--vapidir', meson.current_build_dir(),
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--pkg', 'posix',
    '--pkg', 'sqlite3',
    '--pkg', 'ocsqlite',
    '--pkg', 'gobject-2.0',
    '--pkg', 'glib-2.0',
    '--pkg', 'gio-2.0',
    '--pkg', 'json-glib-1.0',
    '--pkg', 'gee-0.8',
    '--pkg', 'gtk4',
    '--pkg', 'gtksourceview-5',
    '--library', 'occoder',
    '--header', meson.current_build_dir() / 'occoder.h',  # Use header from library
    '--vapi', '@OUTPUT@',
    '@INPUT@'
  ],
  depends: [occoder_base_lib],  # Ensure library is built first (so header exists)
  build_by_default: true,
  install: true,
  install_dir: get_option('datadir') / 'vala' / 'vapi'
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
  includes: ['GObject-2.0', 'Gio-2.0', 'Gtk-4.0', ocsqlite_gir[0]],
  install: true,
  fatal_warnings: false
)

# Create dependency for other libraries to use
# Use link_args instead of link_with to prevent meson from auto-including occoder-meson.vapi
occoder_vapi_dep = declare_dependency(
  link_args: ['-L' + meson.current_build_dir(), '-loccoder'],
  sources: [occoder_vapi[0]],  # Include VAPI file to ensure it's built first
  dependencies: [ocsqlite_vapi_dep]
)
