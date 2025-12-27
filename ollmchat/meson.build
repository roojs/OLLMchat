# Build ollmchat executable (primary application)

# Build rpath for executable to find libraries in build directory
# This allows running executable without installing libraries
build_rpath = ':'.join([
  meson.current_build_dir() / '..' / 'libocsqlite',
  meson.current_build_dir() / '..' / 'libocmarkdown',
  meson.current_build_dir() / '..' / 'libocmarkdowngtk',
  meson.current_build_dir() / '..' / 'libollmchat',
  meson.current_build_dir() / '..' / 'libollmchatgtk'
])

# Dependencies for ollmchat executable
valac = meson.get_compiler('vala')
ollmchat_deps = [
  dependency('gtk4'),
  dependency('libadwaita-1'),
  dependency('gtksourceview-5'),
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('json-glib-1.0'),
  dependency('libsoup-3.0'),
  dependency('libgit2-glib-1.0'),

  valac.find_library('posix'),
]

# Build ollmchat executable (primary application)
# Include resources directly in the executable to ensure they're registered
ollmchat = executable('ollmchat',
  dependencies: [ollmchat_deps, ocmarkdowngtk_vapi_dep, ocsqlite_vapi_dep, ocagent_vapi_dep, occoder_vapi_dep, ocvector_vapi_dep, ocfiles_vapi_dep],
  sources: [
    'Application.vala',
    'Window.vala',
    'WindowPane.vala',
    'Settings/AddModelDialog.vala',
    'Settings/ConnectionAdd.vala',
    'Settings/ConnectionRow.vala',
    'Settings/SettingsPage.vala',
    'Settings/ConnectionsPage.vala',
    'Settings/ModelPullManager.vala',
    'Settings/ModelRow.vala',
    'Settings/ModelsPage.vala',
    'Settings/OptionWidget.vala',
    'Settings/SearchablePulldown.vala',
    'Settings/SettingsDialog.vala',
    ollmchat_resources
  ],
  link_with: [ollmchat_base_lib, ollmchatgtk_lib],  # Use ocvector_vapi_dep (link_args) instead of link_with to avoid ocvector-meson.vapi
  include_directories: [
    include_directories('../libollmchat'),
    include_directories('../libollmchatgtk'),
    include_directories('../libocmarkdown'),
    include_directories('../libocmarkdowngtk'),
    include_directories('../libocvector'),  # For ocvector.h (included by OLLMvector.Tool.CodebaseSearchTool)
    include_directories('../libocagent'),   # For ocagent.h (transitive dependency)
    include_directories('../libocsqlite'),  # For ocsqlite.h (transitive dependency)
    include_directories('../libocfiles')   # For ocfiles.h (transitive dependency)
  ],
  build_rpath: build_rpath,
  # Use --pkg for VAPI access (uses manually generated VAPI files)
  vala_args: [
    '--pkg=ocmarkdown',
    '--pkg=ocmarkdowngtk',
    '--pkg=sqlite3',
    '--pkg=ocsqlite',
    '--pkg=ocagent',
    '--pkg=occoder',
    '--pkg=ocfiles',  # Required for OLLMcoder.Files.BufferProvider and OLLMcoder.Files.GitProvider
    '--pkg=ocvector',  # Use manually generated ocvector.vapi (via ocvector_vapi_dep)
    '--pkg=fiass',  # Required for ocvector.vapi (Faiss.IDSelector)
    '--pkg=libgit2-glib-1.0',
    '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdown',
    '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdowngtk',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libocagent',
    '--vapidir', meson.current_build_dir() / '..' / 'liboccoder',
    '--vapidir', meson.current_build_dir() / '..' / 'libocfiles',
    '--vapidir', meson.current_build_dir() / '..' / 'libocvector'
  ],
  install: true,
  install_dir: get_option('bindir')
)

# Install application icon
install_data(
  '../pixmaps/scalable/apps/org.roojs.ollmchat.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)

# Install desktop file
install_data(
  'org.roojs.ollmchat.desktop',
  install_dir: get_option('datadir') / 'applications'
)
