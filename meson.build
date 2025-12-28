project('ollmchat', 'vala', 'c', 'cpp',
  version: '1.0.0',
  license: 'LGPL',
  default_options: [
    'default_library=shared',
    'c_std=gnu11',
    'cpp_std=c++11',
    'prefix=/usr'
  ]
)

gnome = import('gnome')

valac = meson.get_compiler('vala')
valac_exe = find_program('valac')

add_project_arguments(['--vapidir', meson.current_source_dir() / 'vapi'], language: 'vala')
add_project_arguments(['--vapidir', meson.current_source_dir() / '../vapi'], language: 'vala')
add_project_arguments(['--vapidir', meson.current_build_dir()], language: 'vala')  # Add build dir for generated VAPIs
add_project_arguments(['--target-glib=auto'], language: 'vala')

# Build libraries in dependency order
subdir('libocsqlite')      # No dependencies
subdir('libocmarkdown')    # No dependencies
subdir('libocmarkdowngtk') # Depends on libocmarkdown
subdir('libocagent')       # No dependencies
subdir('libocfiles')       # Depends on libocsqlite
subdir('libollmchat')      # Depends on libocsqlite, libocagent
subdir('libocvector')      # Depends on libocsqlite, libollmchat, libocfiles
subdir('liboccoder')       # Depends on libocsqlite, libocagent, libocfiles, libocvector, libollmchat
subdir('libollmchatgtk')   # Depends on libollmchat, libocmarkdown, libocmarkdowngtk, libocsqlite
subdir('ollmchat')         # Primary application - depends on all libraries
subdir('examples')          # Depends on all libraries

# Create wrapper scripts in top-level build directory for easier access
# These wrappers set up LD_LIBRARY_PATH and execute the real binaries from examples/
wrapper_template = '''#!/bin/bash
# Wrapper script for @EXECUTABLE@
# This script sets up the library path and runs the actual executable

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXECUTABLE="@EXECUTABLE_PATH@"

# Set LD_LIBRARY_PATH as fallback (rpath should work, but this ensures compatibility)
export LD_LIBRARY_PATH="@LIB_PATH@${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Execute the real binary with all arguments
exec "$EXECUTABLE" "$@"
'''

# List of executables and their paths
executables_info = [
  ['ollmchat', 'ollmchat/ollmchat'],
  ['oc-test-cli', 'examples/oc-test-cli'],
  ['oc-test-pull', 'examples/oc-test-pull'],
  ['oc-test-fetch', 'examples/oc-test-fetch'],
  ['oc-test-files', 'examples/oc-test-files'],
  ['ollmchat.bin', 'ollmchat/ollmchat'],  # Wrapper for testing ollama chat with latest code
  ['oc-markdown-test', 'examples/oc-markdown-test'],
  ['oc-html2md', 'examples/oc-html2md'],
  ['oc-md2html', 'examples/oc-md2html'],
  ['oc-diff', 'examples/oc-diff'],
  ['oc-migrate-editors', 'examples/oc-migrate-editors'],
  ['oc-vector-index', 'examples/oc-vector-index'],
  ['oc-vector-search', 'examples/oc-vector-search']
]

# Library paths for LD_LIBRARY_PATH
lib_path = ':'.join([
  meson.current_build_dir() / 'libocsqlite',
  meson.current_build_dir() / 'libocmarkdown',
  meson.current_build_dir() / 'libocmarkdowngtk',
  meson.current_build_dir() / 'libocfiles',
  meson.current_build_dir() / 'liboccoder',
  meson.current_build_dir() / 'libollmchat',
  meson.current_build_dir() / 'libocagent',
  meson.current_build_dir() / 'libollmchatgtk',
  meson.current_build_dir() / 'libocvector'
])

# Create wrapper scripts in top-level build directory
foreach exe_info : executables_info
  exe_name = exe_info[0]
  exe_path = exe_info[1]
  wrapper_content = wrapper_template.replace('@EXECUTABLE@', exe_name)
  wrapper_content = wrapper_content.replace('@EXECUTABLE_PATH@', meson.current_build_dir() / exe_path)
  wrapper_content = wrapper_content.replace('@LIB_PATH@', lib_path)
  
  wrapper_script = custom_target('wrapper-script-' + exe_name,
    output: exe_name,
    input: [],
    command: [
      find_program('bash'),
      '-c',
      'cat > @OUTPUT@ << \'EOF\'\n' + wrapper_content + 'EOF\nchmod +x @OUTPUT@'
    ],
    build_by_default: true,
    install: false,
    build_always_stale: false
  )
endforeach

subdir('docs')             # Depends on all source files

# Post-install script to update icon cache and desktop database
gnome.post_install(
  gtk_update_icon_cache: true,
  update_desktop_database: true
)
