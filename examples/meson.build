# Build test executables

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

# Build test-ollama executable (command-line test)
test_ollama = executable('oc-test-cli',
  dependencies: [test_ollama_deps, ocsqlite_vapi_dep],
  sources: ['oc-test-cli.vala'],
  link_with: [ollmchat_base_lib],  # ollmchat_base_lib already links with ocsqlite via link_args
  include_directories: include_directories('../libollmchat'),
  vala_args: [
    '--pkg=sqlite3',
    '--pkg=ocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite'
  ],
  install: false
)

# Build test-window executable (GTK UI test)
# Include resources directly in the executable to ensure they're registered
# Use ocmarkdowngtk_vapi_dep which provides link_with but with sources to prevent VAPI being added
test_window = executable('oc-test-window',
  dependencies: [test_window_deps, ocmarkdowngtk_vapi_dep, ocsqlite_vapi_dep],
  sources: ['oc-test-window.vala', ollmchat_resources],
  link_with: [ollmchat_base_lib, ollmchatgtk_lib],  # Libraries already link with dependencies via link_args
  include_directories: [
    include_directories('../libollmchat'),
    include_directories('../libollmchatgtk'),
    include_directories('../libocmarkdown'),
    include_directories('../libocmarkdowngtk')
  ],
  # Use --pkg for VAPI access (uses manually generated VAPI files)
  vala_args: [
    '--pkg=ocmarkdown',
    '--pkg=ocmarkdowngtk',
    '--pkg=sqlite3',
    '--pkg=ocsqlite',
    '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdown',
    '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdowngtk',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite'
  ],
  install: false
)

# Build test-html-parser-to-md executable (HTML to Markdown converter)
# Use declare_dependency to avoid meson auto-including ocmarkdown-meson.vapi
test_html_parser_to_md = executable('oc-markdown-html-to-md',
  dependencies: [base_deps, ocmarkdown_vapi_dep],
  sources: ['oc-markdown-html-to-md.vala'],
  vala_args: [
    '--pkg=ocmarkdown',
    '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdown'
  ],
  install: false
)

# Build test-markdown-parser executable (Markdown parser test with dummy renderer)
test_markdown_parser = executable('oc-markdown-test',
  dependencies: test_window_deps,
  sources: ['oc-markdown-test.vala'],
  link_with: [ocmarkdown_base_lib, ocmarkdowngtk_lib],
  include_directories: include_directories('../libocmarkdown'),
  install: false
)

# Build vmd2html executable (Markdown to HTML converter)
# Use declare_dependency to avoid meson auto-including ocmarkdown-meson.vapi
vmd2html = executable('oc-md2html',
  dependencies: [base_deps, ocmarkdown_vapi_dep],
  sources: ['oc-md2html.vala'],
  vala_args: [
    '--pkg=ocmarkdown',
    '--vapidir', meson.current_build_dir() / '..' / 'libocmarkdown'
  ],
  install: false
)
