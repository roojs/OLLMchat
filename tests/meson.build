# Test suite for file operations and markdown parser

# libollamaweb HTML fixture tests (offline)
test_ollamaweb_script = files('test-ollamaweb-parse.sh')
oc_test_ollamaweb_exe = get_variable('test_ollamaweb', disabler())
test('test-ollamaweb-parse',
  find_program('bash'),
  args: [
    test_ollamaweb_script,
    meson.current_build_dir() / '..'
  ],
  depends: [oc_test_ollamaweb_exe],
  workdir: meson.current_source_dir(),
  timeout: 120,
  suite: 'ollamaweb'
)

test_ollamaweb_merge_script = files('test-ollamaweb-merge.sh')
test('test-ollamaweb-merge',
  find_program('bash'),
  args: [
    test_ollamaweb_merge_script,
    meson.current_build_dir() / '..'
  ],
  depends: [oc_test_ollamaweb_exe],
  workdir: meson.current_source_dir(),
  timeout: 60,
  suite: 'ollamaweb'
)


# ollmfilesd RPC shell tests (stdio NDJSON + jq)
test_rpc_script = files('test-rpc.sh')
test_rpc_t1_script = files('test-rpc-t1.sh')
test_rpc_t2_script = files('test-rpc-t2.sh')
ollmfilesd_bin = get_variable('ollmfilesd_bin', disabler())
rpc_test_app_base_vala = configure_file(
  input: '../examples/TestAppBase.vala',
  output: 'TestAppBase.vala',
  copy: true,
)
rpc_test_deps = [
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('json-glib-1.0'),
  dependency('libsoup-3.0'),
  ocrpc_vapi_dep,
  ollmchat_vapi_dep,
  ocsqlite_vapi_dep,
]
rpc_test_link_with = [ollmchat_base_lib]
rpc_test_build_rpath = ':'.join([
  meson.current_build_dir() / '..' / 'libocrpc',
  meson.current_build_dir() / '..' / 'libollmchat',
  meson.current_build_dir() / '..' / 'libocsqlite',
])
rpc_test_vala_args = [
  '--pkg=ocrpc',
  '--pkg=ollmchat',
  '--pkg=ocsqlite',
  '--pkg=sqlite3',
  '--pkg=libsoup-3.0',
  '--pkg=json-glib-1.0',
  '--vapidir', meson.current_build_dir() / '..' / 'libocrpc',
  '--vapidir', meson.current_build_dir() / '..' / 'libollmchat',
  '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
]
rpc_test_app_lib = static_library('rpc-test-app',
  rpc_test_app_base_vala,
  'rpc/RpcTestAppBase.vala',
  dependencies: rpc_test_deps,
  link_with: rpc_test_link_with,
  include_directories: include_directories('../libollmchat'),
  c_args: ['-I' + (meson.current_build_dir() / '../libollmchat')],
  vala_args: rpc_test_vala_args,
  vala_header: 'rpc-test-app.h',
  vala_vapi: 'rpc-test-app.vapi',
)
rpc_test_app_dep = declare_dependency(
  link_with: rpc_test_app_lib,
  include_directories: include_directories('../libollmchat'),
)
test_rpc_bin = executable('test-rpc-bin',
  'rpc/bin-test.vala',
  dependencies: rpc_test_deps + [rpc_test_app_dep],
  link_with: rpc_test_link_with,
  build_rpath: rpc_test_build_rpath,
  vala_args: rpc_test_vala_args,
)
test('test-rpc',
  find_program('bash'),
  args: [
    test_rpc_script,
    meson.current_build_dir() / '..'
  ],
  depends: [ollmfilesd_bin],
  workdir: meson.current_source_dir(),
  timeout: 60,
  suite: 'rpc'
)
test('test-rpc-bin',
  test_rpc_bin,
  suite: 'rpc',
  timeout: 10,
)
test_rpc_live = executable('test-rpc-live-handles',
  'rpc/live-handles-test.vala',
  dependencies: rpc_test_deps + [rpc_test_app_dep],
  link_with: rpc_test_link_with,
  build_rpath: rpc_test_build_rpath,
  vala_args: rpc_test_vala_args,
)
test('test-rpc-live-handles',
  test_rpc_live,
  suite: 'rpc',
  timeout: 10,
)
test_rpc_subscribe = executable('test-rpc-subscribe',
  'rpc/subscribe-test.vala',
  dependencies: rpc_test_deps + [rpc_test_app_dep],
  link_with: rpc_test_link_with,
  build_rpath: rpc_test_build_rpath,
  vala_args: rpc_test_vala_args,
)
test('test-rpc-subscribe',
  test_rpc_subscribe,
  suite: 'rpc',
  timeout: 10,
)
test_rpc_callback = executable('test-rpc-callback',
  'rpc/callback-test.vala',
  dependencies: rpc_test_deps + [rpc_test_app_dep],
  link_with: rpc_test_link_with,
  build_rpath: rpc_test_build_rpath,
  vala_args: rpc_test_vala_args,
)
test('test-rpc-callback',
  test_rpc_callback,
  suite: 'rpc',
  timeout: 10,
)
test_rpc_proxies = executable('test-rpc-proxies',
  'rpc/proxies-test.vala',
  dependencies: rpc_test_deps + [
    rpc_test_app_dep,
    dependency('gio-unix-2.0'),
  ],
  link_with: rpc_test_link_with,
  build_rpath: rpc_test_build_rpath,
  export_dynamic: true,
  vala_args: rpc_test_vala_args,
)
test('test-rpc-proxies',
  test_rpc_proxies,
  suite: 'rpc',
  timeout: 10,
)
test_rpc_values = executable('test-rpc-values',
  'rpc/values-test.vala',
  dependencies: rpc_test_deps + [
    rpc_test_app_dep,
    dependency('gio-unix-2.0'),
  ],
  link_with: rpc_test_link_with,
  build_rpath: rpc_test_build_rpath,
  export_dynamic: true,
  vala_args: rpc_test_vala_args,
)
test('test-rpc-values',
  test_rpc_values,
  suite: 'rpc',
  timeout: 10,
)
test_rpc_gi = executable('test-rpc-gi',
  'rpc/gi-test.vala',
  dependencies: rpc_test_deps + [
    rpc_test_app_dep,
    dependency('gobject-introspection-1.0'),
    dependency('gio-unix-2.0'),
  ],
  link_with: rpc_test_link_with,
  build_rpath: rpc_test_build_rpath,
  export_dynamic: true,
  vala_args: rpc_test_vala_args + [
    '--pkg=gobject-introspection-1.0',
  ],
)
test('test-rpc-gi',
  test_rpc_gi,
  suite: 'rpc',
  timeout: 10,
)
test_rpc_scm = executable('test-rpc-scm-notification',
  'rpc/scm-notification-test.vala',
  dependencies: rpc_test_deps + [
    rpc_test_app_dep,
    dependency('gio-unix-2.0'),
    meson.get_compiler('vala').find_library('posix'),
  ],
  link_with: rpc_test_link_with,
  build_rpath: rpc_test_build_rpath,
  vala_args: rpc_test_vala_args + [
    '--pkg=posix',
  ],
)
test('test-rpc-scm-notification',
  test_rpc_scm,
  suite: 'rpc',
  timeout: 10,
)
test_rpc_scm_response = executable('test-rpc-scm-response',
  'rpc/scm-response-test.vala',
  dependencies: rpc_test_deps + [
    rpc_test_app_dep,
    dependency('gio-unix-2.0'),
    meson.get_compiler('vala').find_library('posix'),
  ],
  link_with: rpc_test_link_with,
  build_rpath: rpc_test_build_rpath,
  export_dynamic: true,
  vala_args: rpc_test_vala_args + [
    '--pkg=posix',
  ],
)
test('test-rpc-scm-response',
  test_rpc_scm_response,
  suite: 'rpc',
  timeout: 10,
)
test('test-rpc-t1',
  find_program('bash'),
  args: [
    test_rpc_t1_script,
    meson.current_build_dir() / '..'
  ],
  depends: [ollmfilesd_bin],
  workdir: meson.current_source_dir(),
  timeout: 120,
  suite: 'rpc'
)
test('test-rpc-t2',
  find_program('bash'),
  args: [
    test_rpc_t2_script,
    meson.current_build_dir() / '..'
  ],
  depends: [ollmfilesd_bin],
  workdir: meson.current_source_dir(),
  timeout: 120,
  suite: 'rpc'
)

# Test script for oc-test-files
test_file_ops_script = files('test-file-ops.sh')

# Get reference to oc-test-files executable from examples subdir
# The executable is built in examples/ subdir, so we reference it via parent scope
oc_test_files_exe = get_variable('test_files', disabler())

# Run the test script
# Pass the build directory so the script can find the oc-test-files binary
# The build directory is the parent of current_build_dir (which is tests/)
test('test-file-ops',
  find_program('bash'),
  args: [
    test_file_ops_script,
    meson.current_build_dir() / '..'  # Pass build directory as argument
  ],
  depends: [oc_test_files_exe],  # Ensure oc-test-files is built first
  workdir: meson.current_source_dir(),
  timeout: 300,  # 5 minute timeout
  suite: 'file-ops'
)

# Markdown parser tests (formatting, blocks, tables)
test_markdown_parser_script = files('test-markdown-parser.sh')
oc_markdown_test_exe = get_variable('test_markdown_parser', disabler())
oc_md2html_exe = get_variable('vmd2html', disabler())
test('test-markdown-parser',
  find_program('bash'),
  args: [
    test_markdown_parser_script,
    meson.current_build_dir() / '..'
  ],
  depends: [oc_markdown_test_exe, oc_md2html_exe],
  workdir: meson.current_source_dir(),
  timeout: 60,
  suite: 'markdown'
)

# Document renderer: round-trip all tests/markdown/*.md (md → JSON in build dir → md, compare)
oc_document_renderer_test_exe = get_variable('test_document_renderer', disabler())
test_markdown_doc_script = files('test-markdown-doc.sh')
test('test-markdown-doc',
  find_program('bash'),
  args: [test_markdown_doc_script, meson.current_build_dir() / '..'],
  depends: [oc_document_renderer_test_exe],
  workdir: meson.current_source_dir(),
  timeout: 60,
  suite: 'markdown'
)

# Bubble tests: run sequentially (is_parallel: false) so they can share TEST_DIR/DB
bubble_build_dir = meson.current_build_dir() / '..'
oc_test_bubble_exe = get_variable('test_bubble', disabler())
foreach part : ['1', '2', '3', '4', '5']
  test('test-bubble-@0@'.format(part),
    find_program('bash'),
    args: [files('test-bubble-@0@.sh'.format(part)), bubble_build_dir],
    depends: [oc_test_bubble_exe],
    workdir: meson.current_source_dir(),
    timeout: 120,
    suite: 'bubble',
    is_parallel: false
  )
endforeach

# Response.Chat.check_back_token — oc-test-loop; assert twelve equidistant repeats trigger detection
oc_test_loop_exe = get_variable('oc_test_loop', disabler())
oc_test_loop_bin = meson.current_build_dir() / '..' / 'examples' / 'oc-test-loop'
test('check-back-token-test',
  find_program('bash'),
  args: [
    '-c',
    'set -e; "$1" "$2" | grep -q "Loop detection: YES"',
    '_',
    oc_test_loop_bin,
    meson.current_source_dir() / 'data' / 'twelve-equidistant-loop.txt',
  ],
  depends: [oc_test_loop_exe],
  suite: 'libollmchat')
