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
test_rpc_tcp_script = files('test-rpc-tcp.sh')
test_rpc_t1_script = files('test-rpc-t1.sh')
test_rpc_t2_script = files('test-rpc-t2.sh')
ollmfilesd_bin = get_variable('ollmfilesd_bin', disabler())
test_rpc_client_tcp = executable('test-rpc-client-tcp',
  'test-rpc-client-tcp.vala',
  dependencies: [
    dependency('gee-0.8'),
    dependency('gio-2.0'),
    dependency('glib-2.0'),
    dependency('gobject-2.0'),
    dependency('json-glib-1.0'),
    ocrpc_vapi_dep,
  ],
  build_rpath: meson.current_build_dir() / '..' / 'libocrpc',
  vala_args: [
    '--pkg=ocrpc',
    '--vapidir', meson.current_build_dir() / '..' / 'libocrpc',
  ],
)
test_rpc_bin = executable('test-rpc-bin',
  'rpc/bin-test.vala',
  dependencies: [
    dependency('gee-0.8'),
    dependency('gio-2.0'),
    dependency('glib-2.0'),
    dependency('gobject-2.0'),
    dependency('json-glib-1.0'),
    ocrpc_vapi_dep,
  ],
  build_rpath: meson.current_build_dir() / '..' / 'libocrpc',
  vala_args: [
    '--pkg=ocrpc',
    '--pkg=json-glib-1.0',
    '--vapidir', meson.current_build_dir() / '..' / 'libocrpc',
  ],
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
test('test-rpc-tcp',
  find_program('bash'),
  args: [
    test_rpc_tcp_script,
    meson.current_build_dir() / '..'
  ],
  depends: [ollmfilesd_bin, test_rpc_client_tcp],
  workdir: meson.current_source_dir(),
  timeout: 60,
  suite: 'rpc'
)
test('test-rpc-bin',
  test_rpc_bin,
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
