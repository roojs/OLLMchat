# Test suite for file operations and markdown parser

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
foreach part : ['1', '2', '3', '4']
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

