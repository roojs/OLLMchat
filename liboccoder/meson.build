# Build occoder library (liboccoder.so) - depends on libocsqlite, libocfiles
#
# NOTE: If you add/remove/change source files in this directory, you MUST also
# update docs/meson.build to include the same files in the valadoc input list.

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
  dependency('libgit2-glib-1.0'),
  valac.find_library('posix'),
]

occoder_src = files([
  'BufferProvider.vala',
  'GitProvider.vala',
  'ProjectMigrate.vala',
  'SearchableDropdown.vala',
  'ProjectDropdown.vala',
  'FileDropdown.vala',
  'SourceView.vala',
  'Diff/Patch.vala',
  'Diff/PatchApplier.vala',
  'Diff/Differ.vala',
  'Prompt/CodeAssistant.vala',
  'Prompt/CodeAssistantProvider.vala',
])

# Build rpath for libraries to find each other in build directory
lib_build_rpath = ':'.join([
  meson.current_build_dir(),
  meson.current_build_dir() / '..' / 'libocsqlite',
  meson.current_build_dir() / '..' / 'libocfiles',
  meson.current_build_dir() / '..' / 'libocmarkdown',
  meson.current_build_dir() / '..' / 'libocmarkdowngtk',
  meson.current_build_dir() / '..' / 'libollmchatgtk'
])

occoder_base_lib = library('occoder',
  dependencies: [occoder_deps, ocsqlite_vapi_dep, ocagent_vapi_dep, ocfiles_vapi_dep],
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
    '--pkg=libgit2-glib-1.0',
    '--pkg=ocagent',
    '--pkg=ocfiles',
    # Put build directories FIRST so we use local VAPIs instead of installed ones
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libocfiles',
    '--vapidir', meson.current_build_dir() / '..' / 'libocagent',
    '--vapidir', '/usr/share/vala/vapi'  # System VAPI directory for libgit2-glib-1.0 (last, so local takes priority)
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
    # Put build directories FIRST so we use local VAPIs instead of installed ones
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libocfiles',
    '--vapidir', meson.current_build_dir() / '..' / 'libocagent',
    '--vapidir', meson.current_build_dir(),
    '--vapidir', meson.current_source_dir() / '../vapi',
    '--vapidir', meson.current_source_dir() / '../../vapi',
    '--vapidir', '/usr/share/vala/vapi',  # System VAPI directory for libgit2-glib-1.0 (last, so local takes priority)
    '--pkg', 'posix',
    '--pkg', 'sqlite3',
    '--pkg', 'ocsqlite',
    '--pkg', 'ocfiles',
    '--pkg', 'ocagent',
    '--pkg', 'gobject-2.0',
    '--pkg', 'glib-2.0',
    '--pkg', 'gio-2.0',
    '--pkg', 'json-glib-1.0',
    '--pkg', 'gee-0.8',
    '--pkg', 'gtk4',
    '--pkg', 'gtksourceview-5',
    '--pkg', 'libgit2-glib-1.0',
    '--library', 'occoder',
    '--header', meson.current_build_dir() / 'occoder.h',  # Use header from library
    '--vapi', '@OUTPUT@',
    '@INPUT@'
  ],
  depends: [occoder_base_lib, ocfiles_vapi],  # Ensure library and ocfiles VAPI are built first
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
  link_with: [ocsqlite_base_lib, ocfiles_base_lib, ocagent_base_lib],
  dependencies: [dependency('sqlite3')],
  extra_args: [
    '--extra-library=ocsqlite',
    '--extra-library=ocfiles',
    '--extra-library=ocagent',
    '--accept-unprefixed'
  ],
  includes: ['GObject-2.0', 'Gio-2.0', 'Gtk-4.0', ocsqlite_gir[0], ocfiles_gir[0], ocagent_gir[0]],
  install: true,
  fatal_warnings: false
)

# Create dependency for other libraries to use
# Use link_args instead of link_with to prevent meson from auto-including occoder-meson.vapi
occoder_vapi_dep = declare_dependency(
  link_args: ['-L' + meson.current_build_dir(), '-loccoder'],
  sources: [occoder_vapi[0]],  # Include VAPI file to ensure it's built first
  dependencies: [ocsqlite_vapi_dep, ocfiles_vapi_dep]
)
