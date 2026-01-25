# Build test executables

# Build rpath for executables to find libraries in build directory
# This allows running executables without installing libraries
build_rpath = ':'.join([
  meson.current_build_dir() / '..' / 'libocsqlite',
  meson.current_build_dir() / '..' / 'libocmarkdown',
  meson.current_build_dir() / '..' / 'libocmarkdowngtk',
  meson.current_build_dir() / '..' / 'libocfiles',
  meson.current_build_dir() / '..' / 'liboccoder',
  meson.current_build_dir() / '..' / 'libollmchat',
  meson.current_build_dir() / '..' / 'libollmchatgtk',
  meson.current_build_dir() / '..' / 'liboctools',
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
  dependencies: [test_ollama_deps, ocsqlite_vapi_dep, octools_vapi_dep],
  sources: ['oc-test-cli.vala'],
  link_with: [ollmchat_base_lib],  # ollmchat_base_lib already links with ocsqlite via link_args
  include_directories: include_directories('../libollmchat'),
  build_rpath: build_rpath,
  vala_args: [
    '--pkg=sqlite3',
    '--pkg=ocsqlite',
    '--pkg=gmodule-2.0',  # Required for ocfiles (TreeBase uses GModule)
    '--pkg=tree-sitter',  # Required for ocfiles and octools (TreeBase and ReadFileSummarize use TreeSitter)
    '--pkg=octools',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'liboctools',
    '--vapidir', meson.current_source_dir() / '../vapi'  # For tree-sitter.vapi
  ],
  install: true,
  install_dir: get_option('datadir') / 'doc' / 'ollmchat'
)

# Build test-pull executable (pull streaming test)
test_pull = executable('oc-test-pull',
  dependencies: [test_ollama_deps, ocsqlite_vapi_dep],
  sources: ['TestAppBase.vala', 'oc-test-pull.vala'],
  link_with: [ollmchat_base_lib],  # ollmchat_base_lib already links with ocsqlite via link_args
  include_directories: include_directories('../libollmchat'),
  build_rpath: build_rpath,
  vala_args: [
    '--pkg=sqlite3',
    '--pkg=ocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite'
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

# Build oc-test-fetch executable (WebFetchTool test)
test_web_fetch = executable('oc-test-fetch',
  dependencies: [test_ollama_deps, ocsqlite_vapi_dep, ocmarkdown_vapi_dep, octools_vapi_dep],
  sources: ['TestAppBase.vala', 'oc-test-fetch.vala'],
  link_with: [ollmchat_base_lib],
  include_directories: include_directories('../libollmchat'),
  build_rpath: build_rpath,
  vala_args: [
    '--pkg=sqlite3',
    '--pkg=ocsqlite',
    '--pkg=gmodule-2.0',  # Required for ocfiles (TreeBase uses GModule)
    '--pkg=tree-sitter',  # Required for ocfiles and octools (TreeBase and ReadFileSummarize use TreeSitter)
    '--pkg=ocmarkdown',
    '--pkg=octools',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdown',
    '--vapidir', meson.current_build_dir() / '..' / 'liboctools',
    '--vapidir', meson.current_source_dir() / '../vapi'  # For tree-sitter.vapi
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
# Now extends TestAppBase and supports multiple file operations
# Supports both dummy and sourceview backends (sourceview requires GTK)
test_files = executable('oc-test-files',
  dependencies: [test_window_deps, ocsqlite_vapi_dep, ocfiles_vapi_dep, ollmchat_vapi_dep, octools_vapi_dep],
  sources: ['TestAppBase.vala', 'oc-test-files.vala'],
  link_with: [ollmchat_base_lib, occoder_base_lib],
  include_directories: [
    include_directories('../libocfiles'),
    include_directories('../libollmchat'),
    include_directories('../liboccoder')
  ],
  build_rpath: build_rpath,
  vala_args: [
    '--pkg=sqlite3',
    '--pkg=ocsqlite',
    '--pkg=gmodule-2.0',  # Required for ocfiles (TreeBase uses GModule)
    '--pkg=tree-sitter',  # Required for ocfiles and octools (TreeBase and ReadFileSummarize use TreeSitter)
    '--pkg=ocfiles',
    '--pkg=ollmchat',
    '--pkg=octools',
    # Don't use --pkg=occoder when linking with occoder_base_lib - meson includes occoder-meson.vapi automatically
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libocfiles',
    '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
    '--vapidir', meson.current_build_dir() / '..' / 'liboccoder',
    '--vapidir', meson.current_build_dir() / '..' / 'liboctools',
    '--vapidir', meson.current_source_dir() / '../vapi'  # For tree-sitter.vapi
  ],
  install: true,
  install_dir: get_option('datadir') / 'doc' / 'ollmchat'
)

# Build oc-test-bubble executable (Bubble class test)
test_bubble = executable('oc-test-bubble',
  dependencies: [
    test_ollama_deps,
    dependency('gio-unix-2.0'),  # Required for UnixInputStream in Bubble.vala
    ocsqlite_vapi_dep,
    ocfiles_vapi_dep,
    ollmchat_vapi_dep,
    octools_vapi_dep
  ],
  sources: ['TestAppBase.vala', 'oc-test-bubble.vala'],
  link_with: [ollmchat_base_lib],
  include_directories: [
    include_directories('../libocfiles'),
    include_directories('../libollmchat'),
    include_directories('../liboctools')
  ],
  build_rpath: build_rpath,
  vala_args: [
    '--pkg=sqlite3',
    '--pkg=ocsqlite',
    '--pkg=gmodule-2.0',  # Required for ocfiles (TreeBase uses GModule)
    '--pkg=tree-sitter',  # Required for ocfiles and octools (TreeBase and ReadFileSummarize use TreeSitter)
    '--pkg=gio-unix-2.0',  # Required for UnixInputStream in Bubble.vala
    '--pkg=ocfiles',
    '--pkg=ollmchat',
    '--pkg=octools',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libocfiles',
    '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
    '--vapidir', meson.current_build_dir() / '..' / 'liboctools',
    '--vapidir', meson.current_source_dir() / '../vapi'  # For tree-sitter.vapi
  ],
  install: true,
  install_dir: get_option('datadir') / 'doc' / 'ollmchat'
)

# Build oc-diff executable (unified diff output)
# Only depends on libocfiles (no GTK or vector search dependencies)
# Diff classes moved from liboccoder to libocfiles
oc_diff = executable('oc-diff',
  dependencies: [base_deps, ocsqlite_vapi_dep, ocfiles_vapi_dep],
  sources: ['oc-diff.vala'],
  include_directories: include_directories('../libocfiles'),
  build_rpath: build_rpath,
  vala_args: [
    '--pkg=sqlite3',
    '--pkg=gmodule-2.0',  # Required for ocfiles (TreeBase uses GModule)
    '--pkg=tree-sitter',  # Required for ocfiles (TreeBase uses TreeSitter)
    '--pkg=ocsqlite',
    '--pkg=ocfiles',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libocfiles',
    '--vapidir', meson.current_source_dir() / '../vapi'  # For tree-sitter.vapi
  ],
  install: true,
  install_dir: get_option('bindir')
)

# Build oc-migrate-editors executable (project migration test)
# Only depends on libocfiles (no GTK or vector search dependencies)
# ProjectMigrate moved from liboccoder to libocfiles
oc_migrate_editors = executable('oc-migrate-editors',
  dependencies: [base_deps, ocsqlite_vapi_dep, ocfiles_vapi_dep],
  sources: ['oc-migrate-editors.vala'],
  include_directories: include_directories('../libocfiles'),
  build_rpath: build_rpath,
  vala_args: [
    '--pkg=sqlite3',
    '--pkg=gmodule-2.0',  # Required for ocfiles (TreeBase uses GModule)
    '--pkg=tree-sitter',  # Required for ocfiles (TreeBase uses TreeSitter)
    '--pkg=ocsqlite',
    '--pkg=ocfiles',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libocfiles',
    '--vapidir', meson.current_source_dir() / '../vapi'  # For tree-sitter.vapi
  ],
  install: true,
  install_dir: get_option('datadir') / 'doc' / 'ollmchat'
)

# Compile resources for ocvector (needed by oc-vector-index)
ocvector_resources = gnome.compile_resources(
  'ocvector-resources',
  '../resources/gresources.xml',
  source_dir: ['../resources/ollmchat-agents/code-assistant', '../resources', '../resources/wrapped-tools', '../resources/ocvector'],
  c_name: 'ocvector_resources'
)

# Build oc-vector-index executable (FAISS test tool)
# Note: Does NOT depend on liboccoder - uses base BufferProviderBase instead
# This allows the indexer to work without GTK dependencies
oc_vector_index = executable('oc-vector-index',
  dependencies: [test_ollama_deps, ocvector_vapi_dep, ocsqlite_vapi_dep, ocfiles_vapi_dep, ollmchat_vapi_dep],
  link_with: [ollmchat_base_lib],  # Use ocvector_vapi_dep (link_args) instead of link_with to avoid ocvector-meson.vapi
  sources: ['TestAppBase.vala', 'VectorAppBase.vala', 'oc-vector-index.vala', ocvector_resources],
  include_directories: [
    include_directories('../libocvector'),
    include_directories('../libollmchat'),
    include_directories('../libocsqlite'),
    include_directories('../libocfiles')
  ],
  build_rpath: build_rpath,
  vala_args: [
    '--pkg=sqlite3',
    '--pkg=json-glib-1.0',
    '--pkg=libsoup-3.0',
    '--pkg=gmodule-2.0',  # Required for ocfiles (TreeBase uses GModule)
    '--pkg=tree-sitter',  # Required for ocfiles (TreeBase uses TreeSitter)
    '--pkg=fiass',
    '--pkg=ollmchat',
    '--pkg=ocvector',  # Use custom ocvector.vapi (ocvector-meson.vapi is deleted)
    '--pkg=ocfiles',
    '--vapidir', meson.current_source_dir() / '../vapi',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
    '--vapidir', meson.current_build_dir() / '..' / 'libocvector',
    '--vapidir', meson.current_build_dir() / '..' / 'libocfiles'
  ],
  install: true,
  install_dir: get_option('bindir')
)

# Build oc-vector-search executable (vector search tool)
# Note: Does NOT depend on liboccoder - uses base BufferProviderBase instead
# This allows the search tool to work without GTK dependencies
oc_vector_search = executable('oc-vector-search',
  dependencies: [test_ollama_deps, ocvector_vapi_dep, ocsqlite_vapi_dep, ocfiles_vapi_dep, ollmchat_vapi_dep],
  link_with: [ollmchat_base_lib],  # Use ocvector_vapi_dep (link_args) instead of link_with to avoid ocvector-meson.vapi
  sources: ['TestAppBase.vala', 'VectorAppBase.vala', 'oc-vector-search.vala'],
  include_directories: [
    include_directories('../libocvector'),
    include_directories('../libollmchat'),
    include_directories('../libocsqlite'),
    include_directories('../libocfiles')
  ],
  build_rpath: build_rpath,
  vala_args: [
    '--pkg=sqlite3',
    '--pkg=json-glib-1.0',
    '--pkg=libsoup-3.0',
    '--pkg=gmodule-2.0',  # Required for ocfiles (TreeBase uses GModule)
    '--pkg=tree-sitter',  # Required for ocfiles (TreeBase uses TreeSitter)
    '--pkg=fiass',
    '--pkg=ollmchat',
    '--pkg=ocvector',  # Use custom ocvector.vapi (ocvector-meson.vapi is deleted)
    '--pkg=ocfiles',
    '--vapidir', meson.current_source_dir() / '../vapi',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
    '--vapidir', meson.current_build_dir() / '..' / 'libocvector',
    '--vapidir', meson.current_build_dir() / '..' / 'libocfiles'
  ],
  install: true,
  install_dir: get_option('bindir')
)

