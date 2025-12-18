# Build test executables

# Build rpath for executables to find libraries in build directory
# This allows running executables without installing libraries
build_rpath = ':'.join([
  meson.current_build_dir() / '..' / 'libocsqlite',
  meson.current_build_dir() / '..' / 'libocmarkdown',
  meson.current_build_dir() / '..' / 'libocmarkdowngtk',
  meson.current_build_dir() / '..' / 'liboccoder',
  meson.current_build_dir() / '..' / 'libollmchat',
  meson.current_build_dir() / '..' / 'libollmchatgtk',
  meson.current_build_dir() / '..' / 'libocvector'
])

# Dependencies for test executables
valac = meson.get_compiler('vala')
test_ollama_deps = [
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('json-glib-1.0'),
  dependency('libsoup-3.0'),
  valac.find_library('posix'),
]

test_window_deps = [
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

base_deps = [
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('json-glib-1.0'),
  dependency('libsoup-3.0'),
  dependency('libxml-2.0'),
  valac.find_library('posix'),
]

# Minimal dependencies for occoder-based tests (only what liboccoder needs)
# Note: liboccoder requires GTK4 and gtksourceview-5 even if we don't use GTK widgets directly
occoder_test_deps = [
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

# Minimal dependencies for ocmarkdown tests (only what libocmarkdown needs)
ocmarkdown_test_deps = [
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('json-glib-1.0'),
  dependency('libsoup-3.0'),
  dependency('libxml-2.0'),
  valac.find_library('posix'),
]

# Build test-ollama executable (command-line test)
test_ollama = executable('oc-test-cli',
  dependencies: [test_ollama_deps, ocsqlite_vapi_dep, ocagent_vapi_dep],
  sources: ['oc-test-cli.vala'],
  link_with: [ollmchat_base_lib],  # ollmchat_base_lib already links with ocsqlite via link_args
  include_directories: include_directories('../libollmchat'),
  build_rpath: build_rpath,
  vala_args: [
    '--pkg=sqlite3',
    '--pkg=ocsqlite',
    '--pkg=ocagent',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libocagent'
  ],
  install: true,
  install_dir: get_option('datadir') / 'doc' / 'ollmchat'
)

# Build test-html-parser-to-md executable (HTML to Markdown converter)
# Use declare_dependency to avoid meson auto-including ocmarkdown-meson.vapi
test_html_parser_to_md = executable('oc-html2md',
  dependencies: [base_deps, ocmarkdown_vapi_dep],
  sources: ['oc-html2md.vala'],
  build_rpath: build_rpath,
  vala_args: [
    '--pkg=ocmarkdown',
    '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdown'
  ],
  install: true,
  install_dir: get_option('bindir')
)

# Build test-markdown-parser executable (Markdown parser test with dummy renderer)
# Only depends on libocmarkdown (not libocmarkdowngtk) since it uses DummyRenderer
# Use ocmarkdown_vapi_dep instead of link_with to avoid meson auto-including ocmarkdown-meson.vapi
test_markdown_parser = executable('oc-markdown-test',
  dependencies: [ocmarkdown_test_deps, ocmarkdown_vapi_dep],
  sources: ['oc-markdown-test.vala'],
  include_directories: include_directories('../libocmarkdown'),
  build_rpath: build_rpath,
  vala_args: [
    '--pkg=ocmarkdown',
    '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdown'
  ],
  install: true,
  install_dir: get_option('datadir') / 'doc' / 'ollmchat'
)

# Build vmd2html executable (Markdown to HTML converter)
# Use declare_dependency to avoid meson auto-including ocmarkdown-meson.vapi
vmd2html = executable('oc-md2html',
  dependencies: [base_deps, ocmarkdown_vapi_dep],
  sources: ['oc-md2html.vala'],
  build_rpath: build_rpath,
  vala_args: [
    '--pkg=ocmarkdown',
    '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdown'
  ],
  install: true,
  install_dir: get_option('bindir')
)

# Build oc-test-files executable (project file scanning test)
# Only depends on liboccoder (which already includes libocsqlite)
# Use occoder_vapi_dep instead of link_with to avoid meson auto-including occoder-meson.vapi
test_files = executable('oc-test-files',
  dependencies: [occoder_test_deps, ocsqlite_vapi_dep, ocagent_vapi_dep, occoder_vapi_dep],
  sources: ['oc-test-files.vala'],
  include_directories: include_directories('../liboccoder'),
  build_rpath: build_rpath,
  vala_args: [
    '--pkg=sqlite3',
    '--pkg=ocsqlite',
    '--pkg=ocagent',
    '--pkg=libgit2-glib-1.0',
    '--pkg=occoder',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libocagent',
    '--vapidir', meson.current_build_dir() / '..' / 'liboccoder'
  ],
  install: true,
  install_dir: get_option('datadir') / 'doc' / 'ollmchat'
)

# Build oc-diff executable (unified diff output)
# Only depends on liboccoder (which already includes libocsqlite)
# Use occoder_vapi_dep instead of link_with to avoid meson auto-including occoder-meson.vapi
oc_diff = executable('oc-diff',
  dependencies: [occoder_test_deps, ocsqlite_vapi_dep, ocagent_vapi_dep, occoder_vapi_dep],
  sources: ['oc-diff.vala'],
  include_directories: include_directories('../liboccoder'),
  build_rpath: build_rpath,
  vala_args: [
    '--pkg=sqlite3',
    '--pkg=ocsqlite',
    '--pkg=ocagent',
    '--pkg=libgit2-glib-1.0',
    '--pkg=occoder',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libocagent',
    '--vapidir', meson.current_build_dir() / '..' / 'liboccoder'
  ],
  install: true,
  install_dir: get_option('bindir')
)

# Build oc-migrate-editors executable (project migration test)
# Only depends on liboccoder (which already includes libocsqlite)
# Use occoder_vapi_dep instead of link_with to avoid meson auto-including occoder-meson.vapi
oc_migrate_editors = executable('oc-migrate-editors',
  dependencies: [occoder_test_deps, ocsqlite_vapi_dep, ocagent_vapi_dep, occoder_vapi_dep],
  sources: ['oc-migrate-editors.vala'],
  include_directories: include_directories('../liboccoder'),
  build_rpath: build_rpath,
  vala_args: [
    '--pkg=sqlite3',
    '--pkg=ocsqlite',
    '--pkg=ocagent',
    '--pkg=libgit2-glib-1.0',
    '--pkg=occoder',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libocagent',
    '--vapidir', meson.current_build_dir() / '..' / 'liboccoder'
  ],
  install: true,
  install_dir: get_option('datadir') / 'doc' / 'ollmchat'
)

# Build oc-vector-index executable (FAISS test tool)
oc_vector_index = executable('oc-vector-index',
  dependencies: [test_ollama_deps, ocvector_vapi_dep],
  sources: ['oc-vector-index.vala'],
  include_directories: [
    include_directories('../libocvector'),
    include_directories('../libollmchat'),
    include_directories('../libocagent'),
    include_directories('../libocsqlite')
  ],
  build_rpath: build_rpath,
  vala_args: [
    '--pkg=sqlite3',
    '--pkg=json-glib-1.0',
    '--pkg=libsoup-3.0',
    '--pkg=fiass',
    '--pkg=ocagent',
    '--pkg=ollmchat',
    '--pkg=ocvector',
    '--vapidir', meson.current_source_dir() / '../vapi',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libocagent',
    '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
    '--vapidir', meson.current_build_dir() / '..' / 'libocvector',
    '--vapidir', meson.current_build_dir() / 'libocvector'
  ],
  install: true,
  install_dir: get_option('bindir')
)

