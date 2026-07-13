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

if get_option('android_shell_poc')
  if host_machine.system() == 'android' and not meson.version().version_compare('>=1.8.0')
    error('android_shell_poc on Android requires Meson >= 1.8.0 for android_exe_type')
  endif

  android_shell_poc_deps = [
    dependency('gtk4'),
    dependency('libadwaita-1'),
    dependency('gio-2.0'),
    dependency('glib-2.0'),
    dependency('gobject-2.0'),
  ]
  android_shell_poc_vala_args = [
    '--pkg=gtk4',
    '--pkg=libadwaita-1',
    '--pkg=gio-2.0',
    '--pkg=glib-2.0',
    '--pkg=gobject-2.0',
  ]

  if host_machine.system() == 'android'
    android_shell_poc_exe = executable('ollmchat-android-shell-poc',
      dependencies: android_shell_poc_deps,
      sources: ['AndroidShellPoc.vala'],
      vala_args: android_shell_poc_vala_args,
      android_exe_type: 'application',
      install: true,
      install_dir: get_option('libdir')
    )
  else
    android_shell_poc_exe = executable('ollmchat-android-shell-poc',
      dependencies: android_shell_poc_deps,
      sources: ['AndroidShellPoc.vala'],
      vala_args: android_shell_poc_vala_args,
      install: true,
      install_dir: get_option('bindir')
    )
  endif

  subdir_done()
endif

# Build rpath for executable to find libraries in build directory
# This allows running executable without installing libraries
build_rpath = ':'.join([
  meson.current_build_dir() / '..' / 'libocsqlite',
  meson.current_build_dir() / '..' / 'libocmarkdown',
  meson.current_build_dir() / '..' / 'libocmarkdowngtk',
  meson.current_build_dir() / '..' / 'libollmchat',
  meson.current_build_dir() / '..' / 'libollmchatgtk',
  meson.current_build_dir() / '..' / 'liboctools',
  meson.current_build_dir() / '..' / 'libocmcp',
  meson.current_build_dir() / '..' / 'libollamaweb',
  meson.current_build_dir() / '..' / 'libocrpc',
  meson.current_build_dir() / '..' / 'ollmfilesd',
])

android_poc_settings_sources = []
if get_option('android_poc')
  android_poc_settings_sources = [
    'SettingsDialog/SettingsPage.vala',
    'SettingsDialog/ConnectionsPage.vala',
    'SettingsDialog/ModelsPage.vala',
    'SettingsDialog/ModelRow.vala',
    'SettingsDialog/AddModelDialog.vala',
    'SettingsDialog/SearchablePulldown.vala',
    'SettingsDialog/PullStatus.vala',
    'SettingsDialog/PullManager.vala',
    'SettingsDialog/PullManagerThread.vala',
    'SettingsDialog/PullManagerBanner.vala',
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
    'SettingsDialog/ConnectionAdd.vala',
    'SettingsDialog/ConnectionRow.vala',
  ]
endif

if get_option('android_poc') and host_machine.system() == 'android'
  if not meson.version().version_compare('>=1.8.0')
    error('android_poc on Android requires Meson >= 1.8.0 for android_exe_type')
  endif

  android_poc_deps = [
    dependency('gtk4'),
    dependency('libadwaita-1'),
    dependency('gtksourceview-5'),
    dependency('gee-0.8'),
    dependency('gio-2.0'),
    dependency('glib-2.0'),
    dependency('gobject-2.0'),
    dependency('json-glib-1.0'),
    dependency('libsoup-3.0'),
    dependency('gioopenssl'),
    valac.find_library('posix'),
  ]

  android_poc_sources = [
    'android/android-gio-tls.c',
    'android/AndroidConnectionTls.vala',
    'android/AndroidConnectionConfigTls.vala',
    version_vala,
    'About.vala',
    'ChatUserInterface.vala',
    'AgentDropdown.vala',
    'BusyDialog.vala',
    'android/AndroidApplication.vala',
    'android/OllmchatWindow.vala',
    'android/MainDialog.vala',
    'android/AndroidTouchDebug.vala',
    'android/AndroidStartup.vala',
    'android/AndroidBootstrapConnectionAdd.vala',
    'android/AndroidToolTypes.vala',
    'android/AndroidToolsRegistration.vala',
    'android/tools/WebFetch/Tool.vala',
    'android/tools/WebFetch/Request.vala',
    'android/tools/SessionFetch/Tool.vala',
    'android/tools/SessionFetch/Request.vala',
    'android/tools/GoogleSearch/Tool.vala',
    'android/tools/GoogleSearch/Request.vala',
    'android/tools/GoogleSearch/Config.vala',
  ] + android_poc_settings_sources

  android_poc = executable('ollmchat-android-poc',
    dependencies: [
      android_poc_deps,
      ocsqlite_vapi_dep,
      ocmarkdown_vapi_dep,
      ocmarkdowngtk_vapi_dep,
      ollmchat_vapi_dep,
      ollmchatgtk_vapi_dep,
      ollamaweb_vapi_dep
    ],
    sources: android_poc_sources,
    link_with: [ollmchat_base_lib, ollmchatgtk_lib],
    include_directories: [
      include_directories('android'),
      include_directories('../libollmchat'),
      include_directories('../libollmchatgtk'),
      include_directories('../libocmarkdowngtk'),
      include_directories('../libollamaweb'),
      include_directories('../libocsqlite')
    ],
    build_rpath: build_rpath,
    # Do not add --pkg=gee-0.8 here: android_poc_deps already lists
    # dependency('gee-0.8'); Meson passes gee-0.8.vapi to valac. A duplicate
    # --pkg breaks Android cross-builds — see docs/android-build.md.
    vala_args: [
      '--define=OLLM_ANDROID',
      '--pkg=gtk4',
      '--pkg=libadwaita-1',
      '--pkg=gtksourceview-5',
      '--pkg=sqlite3',
      '--pkg=ocsqlite',
      '--pkg=ollmchat',
      '--pkg=ollmchatgtk',
      '--pkg=ollamaweb',
      '--pkg=ocmarkdown',
      '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
      '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdown',
      '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
      '--vapidir', meson.current_build_dir() / '..' / 'libollmchatgtk',
      '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdowngtk',
      '--vapidir', meson.current_build_dir() / '..' / 'libollamaweb',
    ],
    android_exe_type: 'application',
    install: true,
    install_dir: get_option('libdir')
  )

  subdir_done()
endif

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

  valac.find_library('posix'),
  cc.find_library('m', required: false),
]

# Windows: embed the same app icon used on Linux (pixmaps/org.roojs.ollmchat.ico).
window_src = 'Window.vala'

ollmchat_sources = [
  version_vala,
  'Application.vala',
  'About.vala',
  'ChatUserInterface.vala',
  'AgentDropdown.vala',
  'BusyDialog.vala',
  'Initialize.vala',
  window_src,
  'WindowPane.vala',
  'FileChangeBanner.vala',
  'ActivityBanner.vala',
  'SettingsDialog/AddModelDialog.vala',
  'SettingsDialog/ConnectionAdd.vala',
  'SettingsDialog/ConnectionRow.vala',
  'SettingsDialog/SettingsPage.vala',
  'SettingsDialog/ConnectionsPage.vala',
  'SettingsDialog/PullStatus.vala',
  'SettingsDialog/PullManager.vala',
  'SettingsDialog/PullManagerThread.vala',
  'SettingsDialog/PullManagerBanner.vala',
  'SettingsDialog/ModelRow.vala',
  'SettingsDialog/ModelsPage.vala',
  'SettingsDialog/ProjectSearchFilter.vala',
  'SettingsDialog/ProjectsPage.vala',
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
]
# VectorRegistry.vala removed — CodebaseSearch is registered via liboctools/Registry.
if host_machine.system() == 'windows'
  win_mod = import('windows')
  ollmchat_sources += win_mod.compile_resources('ollmchat.rc')
endif

# Build ollmchat executable (primary application)
# Include resources directly in the executable to ensure they're registered
ollmchat_exe_deps = [
  ollmchat_deps,
  ocmarkdowngtk_vapi_dep,
  ocsqlite_vapi_dep,
  occoder_vapi_dep,
  ocfiles_vapi_dep,
  octools_vapi_dep,
  ocmcp_vapi_dep,
  ocrpc_vapi_dep,
]
ollmchat_vala_args = [
  '--pkg=ocmarkdown',
  '--pkg=ocmarkdowngtk',
  '--pkg=sqlite3',
  '--pkg=ocsqlite',
  '--pkg=gmodule-2.0',
  '--pkg=tree-sitter',
  '--pkg=occoder',
  '--pkg=ocfiles',
  '--pkg=octools',
  '--pkg=ocmcp',
  '--pkg=ollmchat',
  '--pkg=ollamaweb',
  '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdown',
  '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdowngtk',
  '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
  '--vapidir', meson.current_build_dir() / '..' / 'liboccoder',
  '--vapidir', meson.current_build_dir() / '..' / 'libocfiles',
  '--vapidir', meson.current_build_dir() / '..' / 'liboctools',
  '--vapidir', meson.current_build_dir() / '..' / 'libocmcp',
  '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',  # For ollmchat.vapi
  '--vapidir', meson.current_build_dir() / '..' / 'libollamaweb',
  '--vapidir', meson.current_source_dir() / '../vapi',  # For tree-sitter.vapi
  '--pkg=ocrpc',
  '--vapidir', meson.current_build_dir() / '..' / 'libocrpc',
]

ollmchat = executable('ollmchat',
  dependencies: ollmchat_exe_deps,
  sources: ollmchat_sources,
  link_with: [ollmchat_base_lib, ollmchatgtk_lib],
  include_directories: [
    include_directories('../libollmchat'),
    include_directories('../libollamaweb'),
    include_directories('../libollmchatgtk'),
    include_directories('../libocmarkdown'),
    include_directories('../libocmarkdowngtk'),
    include_directories('../libocsqlite'),  # For ocsqlite.h (transitive dependency)
    include_directories('../libocfiles')   # For ocfiles.h (transitive dependency)
  ],
  build_rpath: build_rpath,
  # Use --pkg for VAPI access (uses manually generated VAPI files)
  vala_args: ollmchat_vala_args,
  install: true,
  install_dir: get_option('bindir')
)

if get_option('android_poc') and host_machine.system() != 'android'
  android_poc_deps = [
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

  android_poc_sources = [
    'android/android-gio-tls.c',
    'android/AndroidConnectionTls.vala',
    'android/AndroidConnectionConfigTls.vala',
    version_vala,
    'About.vala',
    'ChatUserInterface.vala',
    'AgentDropdown.vala',
    'BusyDialog.vala',
    'android/AndroidApplication.vala',
    'android/OllmchatWindow.vala',
    'android/MainDialog.vala',
    'android/AndroidTouchDebug.vala',
    'android/AndroidStartup.vala',
    'android/AndroidBootstrapConnectionAdd.vala',
    'android/AndroidToolTypes.vala',
    'android/AndroidToolsRegistration.vala',
    'android/tools/WebFetch/Tool.vala',
    'android/tools/WebFetch/Request.vala',
    'android/tools/SessionFetch/Tool.vala',
    'android/tools/SessionFetch/Request.vala',
    'android/tools/GoogleSearch/Tool.vala',
    'android/tools/GoogleSearch/Request.vala',
    'android/tools/GoogleSearch/Config.vala',
  ] + android_poc_settings_sources

  android_poc_vala_args = [
    # Do not add --pkg=gee-0.8 — dependency('gee-0.8') in android_poc_deps
    # is enough; see docs/android-build.md.
    '--define=OLLM_ANDROID',
    '--pkg=gtk4',
    '--pkg=libadwaita-1',
    '--pkg=gtksourceview-5',
    '--pkg=sqlite3',
    '--pkg=ocsqlite',
    '--pkg=ollmchat',
    '--pkg=ollmchatgtk',
    '--pkg=ollamaweb',
    '--pkg=ocmarkdown',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
    '--vapidir', meson.current_build_dir() / '..' / 'libollmchatgtk',
    '--vapidir', meson.current_build_dir() / '..' / 'libollamaweb',
    '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdown',
  ]

  android_poc = executable('ollmchat-android-poc',
    dependencies: [
      android_poc_deps,
      ocsqlite_vapi_dep,
      ocmarkdown_vapi_dep,
      ocmarkdowngtk_vapi_dep,
      ollmchat_vapi_dep,
      ollmchatgtk_vapi_dep,
      ollamaweb_vapi_dep
    ],
    sources: android_poc_sources,
    link_with: [ollmchat_base_lib, ollmchatgtk_lib],
    include_directories: [
      include_directories('android'),
      include_directories('../libollmchat'),
      include_directories('../libollmchatgtk'),
      include_directories('../libocmarkdowngtk'),
      include_directories('../libollamaweb'),
      include_directories('../libocsqlite')
    ],
    build_rpath: build_rpath,
    vala_args: android_poc_vala_args,
    install: true,
    install_dir: get_option('bindir')
  )
endif

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

# Dependencies for ollmchat-cli executable (CLI tool, no GTK)
valac = meson.get_compiler('vala')
ollmchat_cli_deps = [
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('json-glib-1.0'),
  dependency('libsoup-3.0'),
  valac.find_library('posix'),
]

# Build rpath for ollmchat-cli executable
ollmchat_cli_build_rpath = ':'.join([
  meson.current_build_dir() / '..' / 'libocrpc',
  meson.current_build_dir() / '..' / 'ollmfilesd',
  meson.current_build_dir() / '..' / 'libocfiles',
  meson.current_build_dir() / '..' / 'libollmchat',
  meson.current_build_dir() / '..' / 'liboctools',
  meson.current_build_dir() / '..' / 'libocmcp'
])

# ollmchat-cli — RPC client; spawns ollmfilesd when needed.
ollmchat_cli = executable('ollmchat-cli',
  dependencies: [
    ollmchat_cli_deps,
    ocfiles_vapi_dep,
    ollmchat_vapi_dep,
    octools_vapi_dep,
    ocmcp_vapi_dep,
    ocrpc_vapi_dep,
  ],
  sources: ['ollmchat-cli.vala'],
  link_with: [ollmchat_base_lib],
  include_directories: [
    include_directories('../libollmchat'),
    include_directories('../libollamaweb'),
    include_directories('../libocfiles'),
    include_directories('../libocsqlite')
  ],
  build_rpath: ollmchat_cli_build_rpath,
  vala_args: [
    '--pkg=gmodule-2.0',
    '--pkg=tree-sitter',
    '--pkg=ocfiles',
    '--pkg=ocrpc',
    '--pkg=ollmchat',
    '--pkg=octools',
    '--pkg=ocmcp',
    '--vapidir', meson.current_build_dir() / '..' / 'libocfiles',
    '--vapidir', meson.current_build_dir() / '..' / 'libocrpc',
    '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
    '--vapidir', meson.current_build_dir() / '..' / 'liboctools',
    '--vapidir', meson.current_build_dir() / '..' / 'libocmcp',
    '--vapidir', meson.current_source_dir() / '../vapi'
  ],
  install: true,
  install_dir: get_option('bindir')
)
