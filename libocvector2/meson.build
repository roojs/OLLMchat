# libocvector2 — vector index/search without libocfiles or tree-sitter

valac = meson.get_compiler('vala')
cpp = meson.get_compiler('cpp')
cpp_std_lib = cpp.find_library('stdc++', required: true)

faiss_wrapper_src = files('faiss_c_wrapper.cpp')
faiss_wrapper_hdr = files('faiss_c_wrapper.h')

ocvector2_deps = [
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
]

ocvector2_src = files([
  'Index.vala',
  'Database.vala',
  'VectorBase.vala',
  'VectorToolConfig.vala',
  'SQT/VectorMetadata.vala',
  'VectorBuilder.vala',
  'Search.vala',
])

lib_build_rpath = ':'.join([
  meson.current_build_dir(),
  meson.current_build_dir() / '..' / 'libocsqlite',
  meson.current_build_dir() / '..' / 'libollmchat',
  meson.current_build_dir() / '..' / 'libollamaweb',
])

ocvector2_base_lib = library('ocvector2',
  dependencies: [ocvector2_deps, ocvector_link_dep, ocsqlite_vapi_dep, ollmchat_vapi_dep],
  sources: ocvector2_src + faiss_wrapper_src,
  link_with: [ollmchat_base_lib],
  vala_header: 'ocvector2.h',
  vala_vapi: 'ocvector2-meson.vapi',
  build_rpath: lib_build_rpath,
  include_directories: [
    include_directories('.'),
    include_directories('..' / 'libollmchat'),
    include_directories('..' / 'libollamaweb'),
    include_directories('..' / 'libocsqlite'),
  ],
  vala_args: [
    '--pkg=sqlite3',
    '--pkg=json-glib-1.0',
    '--pkg=libsoup-3.0',
    '--pkg=gmodule-2.0',
    '--pkg=fiass',
    '--pkg=ollmchat',
    '--pkg=ollamaweb',
    '--pkg=ocsqlite',
    '--vapidir', meson.current_source_dir() / '../vapi',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
    '--vapidir', meson.current_build_dir() / '..' / 'libollamaweb',
  ],
  install: true
)

ocvector2_vapi = custom_target('ocvector2-vapi',
  output: 'ocvector2.vapi',
  input: ocvector2_src,
  command: [
    valac_exe,
    '-C', '--debug',
    '--target-glib=auto',
    '--vapidir', meson.current_source_dir() / '../vapi',
    '--vapidir', meson.current_source_dir() / '../../vapi',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
    '--vapidir', meson.current_build_dir() / '..' / 'libollamaweb',
    '--vapidir', '/usr/share/vala/vapi',
    '--pkg', 'posix',
    '--pkg', 'sqlite3',
    '--pkg', 'json-glib-1.0',
    '--pkg', 'libsoup-3.0',
    '--pkg', 'gmodule-2.0',
    '--pkg', 'fiass',
    '--pkg', 'ollmchat',
    '--pkg', 'ollamaweb',
    '--pkg', 'ocsqlite',
    '--pkg', 'gobject-2.0',
    '--pkg', 'glib-2.0',
    '--pkg', 'gio-2.0',
    '--pkg', 'gee-0.8',
    '--header', meson.current_build_dir() / 'ocvector2.h',
    '--vapi', '@OUTPUT@',
    '@INPUT@'
  ],
  depends: [ocvector2_base_lib, ollamaweb_vapi],
  build_by_default: true,
  install: true,
  install_dir: get_option('datadir') / 'vala' / 'vapi'
)

ocvector2_vapi_dep = declare_dependency(
  link_args: ['-L' + meson.current_build_dir(), '-locvector2'],
  sources: [ocvector2_vapi[0]],
  dependencies: [ocsqlite_vapi_dep, ollmchat_vapi_dep, ocvector_link_dep]
)
