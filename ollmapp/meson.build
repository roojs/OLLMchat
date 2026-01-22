# Build ollmchat executable (primary application)

# Extract git commit date for version (format: 0.YYYYMMDD)
git = find_program('git', required: false)
if git.found()
	git_commit_date = run_command(
		git, 'log', '-1', '--format=%cd', '--date=format:%Y%m%d',
		check: false
	).stdout().strip()
	if git_commit_date == ''
		git_commit_date = '0.00000000'
	else
		git_commit_date = '0.' + git_commit_date
	endif
else
	git_commit_date = '0.00000000'
endif

# Generate version.vala file with version constant
version_vala = configure_file(
	input: 'version.vala.in',
	output: 'version.vala',
	configuration: {
		'APP_VERSION': git_commit_date
	}
)

# Build rpath for executable to find libraries in build directory
# This allows running executable without installing libraries
build_rpath = ':'.join([
  meson.current_build_dir() / '..' / 'libocsqlite',
  meson.current_build_dir() / '..' / 'libocmarkdown',
  meson.current_build_dir() / '..' / 'libocmarkdowngtk',
  meson.current_build_dir() / '..' / 'libollmchat',
  meson.current_build_dir() / '..' / 'libollmchatgtk',
  meson.current_build_dir() / '..' / 'liboctools'
])

# Dependencies for ollmchat executable
valac = meson.get_compiler('vala')
cc = meson.get_compiler('c')
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
  cc.find_library('m', required: false),
]

# Build ollmchat executable (primary application)
# Include resources directly in the executable to ensure they're registered
ollmchat = executable('ollmchat',
  dependencies: [
      ollmchat_deps, 
      ocmarkdowngtk_vapi_dep, 
      ocsqlite_vapi_dep, 
      occoder_vapi_dep, 
      ocvector_vapi_dep, 
      ocfiles_vapi_dep, 
      octools_vapi_dep
  ],
  sources: [
    version_vala,
    'Application.vala',
    'About.vala',
    'Window.vala',
    'WindowPane.vala',
    'FileChangeBanner.vala',
    'VectorScanBanner.vala',
    'SettingsDialog/AddModelDialog.vala',
    'SettingsDialog/ConnectionAdd.vala',
    'SettingsDialog/ConnectionRow.vala',
    'SettingsDialog/SettingsPage.vala',
    'SettingsDialog/CheckingConnectionDialog.vala',
    'SettingsDialog/ConnectionsPage.vala',
    'SettingsDialog/PullStatus.vala',
    'SettingsDialog/PullManager.vala',
    'SettingsDialog/PullManagerThread.vala',
    'SettingsDialog/PullManagerBanner.vala',
    'SettingsDialog/ModelRow.vala',
    'SettingsDialog/ModelsPage.vala',
    'SettingsDialog/SearchablePulldown.vala',
    'SettingsDialog/MainDialog.vala',
    'SettingsDialog/ToolsPage.vala',
    'SettingsDialog/Rows/ToolRow.vala',
    'SettingsDialog/Rows/Row.vala',
    'SettingsDialog/Rows/Bool.vala',
    'SettingsDialog/Rows/String.vala',
    'SettingsDialog/Rows/Connection.vala',
    'SettingsDialog/Rows/Model.vala',
    'SettingsDialog/Rows/ModelUsage.vala',
    'SettingsDialog/Rows/Options.vala',
    'SettingsDialog/Rows/FloatRow.vala',
    'SettingsDialog/Rows/IntRow.vala',
    ollmchat_resources
  ],
  link_with: [ollmchat_base_lib, ollmchatgtk_lib],  # Use ocvector_vapi_dep (link_args) instead of link_with to avoid ocvector-meson.vapi
  include_directories: [
    include_directories('../libollmchat'),
    include_directories('../libollmchatgtk'),
    include_directories('../libocmarkdown'),
    include_directories('../libocmarkdowngtk'),
    include_directories('../libocvector'),  # For ocvector.h (included by OLLMvector.Tool.CodebaseSearchTool)
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
    '--pkg=gmodule-2.0',  # Required for ocfiles (TreeBase uses GModule)
    '--pkg=tree-sitter',  # Required for ocfiles and octools (TreeBase and ReadFileSummarize use TreeSitter)
    '--pkg=occoder',
    '--pkg=ocfiles',  # Required for OLLMcoder.Files.BufferProvider and OLLMcoder.Files.GitProvider
    '--pkg=ocvector',  # Use manually generated ocvector.vapi (via ocvector_vapi_dep)
    '--pkg=octools',  # Tools library
    '--pkg=ollmchat',  # Required for OLLMchat types (Call, Settings, History, etc.)
    '--pkg=fiass',  # Required for ocvector.vapi (Faiss.IDSelector)
    '--pkg=libgit2-glib-1.0',
    '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdown',
    '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdowngtk',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'liboccoder',
    '--vapidir', meson.current_build_dir() / '..' / 'libocfiles',
    '--vapidir', meson.current_build_dir() / '..' / 'libocvector',
    '--vapidir', meson.current_build_dir() / '..' / 'liboctools',
    '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',  # For ollmchat.vapi
    '--vapidir', meson.current_source_dir() / '../vapi'  # For tree-sitter.vapi
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
