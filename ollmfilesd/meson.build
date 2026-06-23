# ollmfilesd — headless file service daemon
#
# BANNED: do not add ocfiles_vapi_dep, --pkg=ocfiles, or libocfiles link/vapidir here.
# BANNED: no OLLMfiles namespace in ollmfilesd sources (use OLLMfilesd + OLLMrpc only).
# Server types live under ollmfilesd/*.vala; shared RPC wire types use libocrpc (OLLMrpc).

valac = meson.get_compiler('vala')
tree_sitter_lib = dependency('tree-sitter', required: true)
is_windows = host_machine.system() == 'windows'

ollmfilesd_deps = [
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('gmodule-2.0'),
  dependency('json-glib-1.0'),
  dependency('libsoup-3.0'),
  dependency('sqlite3'),
  valac.find_library('posix'),
  tree_sitter_lib,
  ocsqlite_vapi_dep,
  ocrpc_vapi_dep,
  ollmchat_vapi_dep,
  ocvector2_vapi_dep,
]
ollmfilesd_vapi_pkgs = []
if not is_windows
  ollmfilesd_deps += dependency('gio-unix-2.0')
  ollmfilesd_vapi_pkgs += '--pkg=gio-unix-2.0'
endif

ollmfilesd_src = files(
  'BufferProviderBase.vala',
  'CallParam.vala',
  'DeleteManager.vala',
  'FileChange.vala',
  'FileBuffer.vala',
  'DummyFileBuffer.vala',
  # Symlink → ../libocfiles/Copyable.vala (listed here so meson C paths stay under ollmfilesd/)
  'Copyable.vala',
  'FileBase.vala',
  'FileHistory.vala',
  'FileAlias.vala',
  'File.vala',
  'FolderFiles.vala',
  'GitProviderBase.vala',
  'ProjectFile.vala',
  'ReviewFiles.vala',
  'ProjectFiles.vala',
  'Folder.vala',
  'Codebase.vala',
  'ProjectList.vala',
  'TreeBase.vala',
  'Tree.vala',
  'ProjectMigrate.vala',
  'ProjectManager.vala',
  'Daemon.vala',
  'StdioConnection.vala',
  'Stdio.vala',
  'Application.vala',
  'Vector/PromptTemplate.vala',
  'Vector/Tree.vala',
  'Vector/DocumentationTree.vala',
  'Vector/Analysis.vala',
  'Vector/DocumentationAnalysis.vala',
  'Vector/FolderAnalysis.vala',
  'Vector/ProjectAnalysis.vala',
  'Vector/ImageAnalyzer.vala',
  'Vector/Indexer.vala',
  'Vector/BackgroundScan.vala',
  'Vector/SearchResult.vala',
)

build_rpath = ':'.join([
  meson.current_build_dir() / '..' / 'libocsqlite',
  meson.current_build_dir() / '..' / 'libocrpc',
  meson.current_build_dir() / '..' / 'libollmchat',
  meson.current_build_dir() / '..' / 'libollamaweb',
  meson.current_build_dir() / '..' / 'libocvector2',
])

ollmfilesd_bin = executable('ollmfilesd',
  ollmfilesd_src,
  dependencies: ollmfilesd_deps,
  link_with: [ollmchat_base_lib],
  include_directories: [
    include_directories('../libollmchat'),
    include_directories('../libollamaweb'),
    include_directories('../libocsqlite'),
    include_directories('../libocrpc'),
    include_directories('../libocvector2'),
  ],
  build_rpath: build_rpath,
  install: true,
  vala_args: strcasestr_vala_args + [
    '--pkg=sqlite3',
    '--pkg=json-glib-1.0',
    '--pkg=gmodule-2.0',
    '--pkg=tree-sitter',
    '--pkg=ocsqlite',
    '--pkg=ocrpc',
    '--pkg=ollmchat',
    '--pkg=ollamaweb',
    '--pkg=fiass',
    '--pkg=ocvector2',
    '--pkg=libsoup-3.0',
  ] + ollmfilesd_vapi_pkgs + [
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libocrpc',
    '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
    '--vapidir', meson.current_build_dir() / '..' / 'libollamaweb',
    '--vapidir', meson.current_build_dir() / '..' / 'libocvector2',
    '--vapidir', meson.current_source_dir() / '../vapi',
    '--vapidir', '/usr/share/vala/vapi',
  ],
)
