# Build ocvector library (libocvector.so)
# v2testing=true: stub OLLMvector.Registry only (V2/Registry.vala)
# v2testing=false: full semantic search (FAISS, indexing, CodebaseSearchTool)

valac = meson.get_compiler('vala')
valac_exe = find_program('valac')

lib_build_rpath = ':'.join([
  meson.current_build_dir(),
  meson.current_build_dir() / '..' / 'libocsqlite',
  meson.current_build_dir() / '..' / 'libocfiles',
  meson.current_build_dir() / '..' / 'libollmchat',
  meson.current_build_dir() / '..' / 'libollamaweb',
])

ocvector_include_dirs = [
  include_directories('.'),
  include_directories('..' / 'libollmchat'),
  include_directories('..' / 'libollamaweb'),
  include_directories('..' / 'libocsqlite'),
  include_directories('..' / 'libocfiles'),
]

ocvector_vapi_vapidirs = [
  '--vapidir', meson.current_source_dir() / '../vapi',
  '--vapidir', meson.current_source_dir() / '../../vapi',
  '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
  '--vapidir', meson.current_build_dir() / '..' / 'libocfiles',
  '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
  '--vapidir', meson.current_build_dir() / '..' / 'libollamaweb',
  '--vapidir', meson.current_build_dir() / '..' / 'libocrpc',
  '--vapidir', '/usr/share/vala/vapi',
]

if get_option('v2testing')
  ocvector_src = files([
    'V2/Registry.vala',
  ])
  ocvector_extra_src = files()
  ocvector_lib_deps = [
    dependency('gee-0.8'),
    dependency('glib-2.0'),
    dependency('gobject-2.0'),
    dependency('json-glib-1.0'),
    dependency('libsoup-3.0'),
    valac.find_library('posix'),
    ollmchat_vapi_dep,
    ocfiles_vapi_dep,
    ocrpc_vapi_dep,
    ocsqlite_vapi_dep,
  ]
  ocvector_link_extra = declare_dependency()
  ocvector_link_with = []
  ocvector_vala_args = [
    '--pkg=libsoup-3.0',
    '--pkg=json-glib-1.0',
    '--pkg=ollmchat',
    '--pkg=ocfiles',
    '--pkg=ocrpc',
    '--pkg=ocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
    '--vapidir', meson.current_build_dir() / '..' / 'libocfiles',
    '--vapidir', meson.current_build_dir() / '..' / 'libocrpc',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
  ]
  ocvector_vapi_pkgs = [
    '--pkg', 'posix',
    '--pkg', 'sqlite3',
    '--pkg', 'json-glib-1.0',
    '--pkg', 'libsoup-3.0',
    '--pkg', 'gmodule-2.0',
    '--pkg', 'tree-sitter',
    '--pkg', 'ocsqlite',
    '--pkg', 'ocrpc',
    '--pkg', 'ocfiles',
    '--pkg', 'ollmchat',
    '--pkg', 'ollamaweb',
    '--pkg', 'gobject-2.0',
    '--pkg', 'glib-2.0',
    '--pkg', 'gio-2.0',
    '--pkg', 'gee-0.8',
  ]
  ocvector_vapi_dep_extra = declare_dependency()
else
  cpp = meson.get_compiler('cpp')
  cpp_std_lib = cpp.find_library('stdc++', required: true)
  faiss_wrapper_src = files('faiss_c_wrapper.cpp')

  ocvector_src = files([
    'Index.vala',
    'Database.vala',
    'VectorBase.vala',
    'Indexing/Tree.vala',
    'Indexing/PromptTemplate.vala',
    'Indexing/Analysis.vala',
    'Indexing/VectorBuilder.vala',
    'Indexing/DocumentationTree.vala',
    'Indexing/DocumentationAnalysis.vala',
    'Indexing/FolderAnalysis.vala',
    'Indexing/ProjectAnalysis.vala',
    'Indexing/ImageAnalyzer.vala',
    'Indexing/DocumentationVectorBuilder.vala',
    'Indexing/Indexer.vala',
    'Search/Search.vala',
    'Search/SearchResult.vala',
    'Tool/CodebaseSearchTool.vala',
    'Tool/CodebaseSearchToolConfig.vala',
    'Tool/RequestCodebaseSearch.vala',
    'Registry.vala',
    'BackgroundScan.vala',
  ])
  ocvector_extra_src = faiss_wrapper_src
  ocvector_lib_deps = [
    dependency('gee-0.8'),
    dependency('gio-2.0'),
    dependency('glib-2.0'),
    dependency('gobject-2.0'),
    dependency('gmodule-2.0'),
    dependency('json-glib-1.0'),
    dependency('libsoup-3.0'),
    dependency('sqlite3'),
    valac.find_library('posix'),
    faiss_dep,
    cpp_std_lib,
    tree_sitter_dep,
    ocvector_link_dep,
    ocsqlite_vapi_dep,
    ollmchat_vapi_dep,
    ocfiles_vapi_dep,
  ]
  ocvector_link_extra = ocvector_link_dep
  ocvector_link_with = [ollmchat_base_lib]
  ocvector_vala_args = [
    '--pkg=sqlite3',
    '--pkg=json-glib-1.0',
    '--pkg=libsoup-3.0',
    '--pkg=gmodule-2.0',
    '--pkg=fiass',
    '--pkg=tree-sitter',
    '--pkg=ocfiles',
    '--pkg=ollmchat',
    '--pkg=ollamaweb',
    '--pkg=ocsqlite',
    '--vapidir', meson.current_source_dir() / '../vapi',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libocfiles',
    '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
    '--vapidir', meson.current_build_dir() / '..' / 'libollamaweb',
  ]
  ocvector_vapi_pkgs = [
    '--pkg', 'posix',
    '--pkg', 'sqlite3',
    '--pkg', 'json-glib-1.0',
    '--pkg', 'libsoup-3.0',
    '--pkg', 'gmodule-2.0',
    '--pkg', 'fiass',
    '--pkg', 'tree-sitter',
    '--pkg', 'ocfiles',
    '--pkg', 'ollmchat',
    '--pkg', 'ollamaweb',
    '--pkg', 'ocsqlite',
    '--pkg', 'gobject-2.0',
    '--pkg', 'glib-2.0',
    '--pkg', 'gio-2.0',
    '--pkg', 'gee-0.8',
  ]
  ocvector_vapi_dep_extra = ocvector_link_dep
endif

ocvector_base_lib = library(ocvector_lib,
  dependencies: ocvector_lib_deps,
  sources: ocvector_src + ocvector_extra_src,
  link_with: ocvector_link_with,
  vala_header: 'ocvector.h',
  vala_vapi: 'ocvector-meson.vapi',
  build_rpath: lib_build_rpath,
  include_directories: ocvector_include_dirs,
  vala_args: ocvector_vala_args,
  install: true
)

ocvector_vapi = custom_target('ocvector-vapi',
  output: 'ocvector.vapi',
  input: ocvector_src,
  command: [
    valac_exe,
    '-C', '--debug',
    '--target-glib=auto',
  ] + ocvector_vapi_vapidirs + ocvector_vapi_pkgs + [
    '--header', meson.current_build_dir() / 'ocvector.h',
    '--vapi', '@OUTPUT@',
    '@INPUT@',
  ],
  depends: [ocvector_base_lib, ollamaweb_vapi, ocfiles_vapi],
  build_by_default: true,
  install: true,
  install_dir: get_option('datadir') / 'vala' / 'vapi'
)

ocvector_vapi_dep = declare_dependency(
  link_args: ['-L' + meson.current_build_dir(), '-l' + ocvector_lib],
  sources: [ocvector_vapi[0]],
  dependencies: [ocfiles_vapi_dep, ollmchat_vapi_dep, ocvector_vapi_dep_extra]
)
