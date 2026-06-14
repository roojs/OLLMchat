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
fs = import('fs')

android_shell_poc = get_option('android_shell_poc')
android_poc_opt = get_option('android_poc')
android_cross_build = host_machine.system() == 'android' and (android_shell_poc or android_poc_opt)

if android_shell_poc and android_poc_opt
  error('android_shell_poc and android_poc are mutually exclusive')
endif

if android_cross_build
  g_ir_compiler = disabler()
else
  g_ir_compiler = find_program('g-ir-compiler')
  gir_typelib_script = meson.project_source_root() / 'scripts/compile-gir-typelib.sh'
  gir_fix_sed = meson.project_source_root() / 'scripts/fix-gir-dep-names.sed'
  if not fs.exists(gir_typelib_script)
    error('GIR typelib helper missing (add to git): ' + gir_typelib_script)
  endif
  if not fs.exists(gir_fix_sed)
    error('GIR name fix-up missing (add to git): ' + gir_fix_sed)
  endif
endif

valac = meson.get_compiler('vala')
valac_exe = find_program('valac')
cc = meson.get_compiler('c')

# Optional libc fast path for ASCII caseless search (DummyFileBuffer.index_of_caseless).
have_strcasestr = cc.has_function(
  'strcasestr',
  args: '-D_GNU_SOURCE',
  prefix: '#include <string.h>',
)
strcasestr_vala_args = []
if have_strcasestr
  strcasestr_vala_args += '--define=HAVE_STRCASESTR'
endif

add_project_arguments(['--vapidir', meson.current_source_dir() / 'vapi'], language: 'vala')
add_project_arguments(['--vapidir', meson.current_source_dir() / '../vapi'], language: 'vala')
add_project_arguments(['--vapidir', meson.current_build_dir()], language: 'vala')  # Add build dir for generated VAPIs
add_project_arguments(['--target-glib=auto'], language: 'vala')

# Vala #if G_OS_WIN32 is not set automatically when cross-compiling on Linux.
if host_machine.system() == 'windows'
  add_project_arguments(['--define=G_OS_WIN32'], language: 'vala')
endif

local_gguf_enabled = false

if android_cross_build
  bundle_sysroot = ''
  bundle_windows_prefix = ''
else
  subdir('config')
endif

sqgi_vala_args = []
if bundle_sysroot != ''
  sqgi_vala_args += [
    '--vapidir', bundle_sysroot / 'usr' / 'share' / 'vala' / 'vapi',
    '--girdir', bundle_sysroot / 'usr' / 'share' / 'gir-1.0',
  ]
endif
if bundle_windows_prefix != ''
  sqgi_vala_args += [
    '--vapidir', bundle_windows_prefix / 'share' / 'vala' / 'vapi',
    '--girdir', bundle_windows_prefix / 'share' / 'gir-1.0',
  ]
endif
if sqgi_vala_args.length() > 0
  add_project_arguments(sqgi_vala_args, language: 'vala')
endif

# Build libraries in dependency order
if android_shell_poc
  subdir('ollmapp')         # Minimal Android APK shell target only
elif android_poc_opt and host_machine.system() == 'android'
  subdir('libocmarkdown')
  subdir('libocsqlite')
  subdir('libollamaweb')
  subdir('libollmchat')
  subdir('ollmapp')         # Remote-chat Android APK target
else
  subdir('libocsqlite')      # No dependencies
  subdir('libocrpc')         # JSON-RPC wire types — no OLLMfiles dependency
  subdir('libocmarkdown')    # No dependencies
  subdir('libollamaweb')     # No dependencies on libollmchat (Phase 1)
  subdir('libocmarkdowngtk') # Depends on libocmarkdown
  subdir('libocfiles')       # Depends on libocsqlite
  subdir('libollmchat')      # Depends on libocsqlite
  subdir('libocvector2')     # Depends on libocsqlite, libollmchat (no libocfiles)
  if host_machine.system() != 'windows'
    subdir('ollmfilesd')     # Headless file daemon — Unix sockets + fork; not on Windows yet
  endif
  subdir('libocmcp')         # Depends on libollmchat, libocfiles
  subdir('liboctools')       # Depends on libollmchat, libocfiles
  subdir('libocvector')      # Depends on libocsqlite, libollmchat, libocfiles
  subdir('liboccoder')       # Depends on libocsqlite, libocfiles, libocvector, libollmchat
  subdir('libollmchatgtk')   # Depends on libollmchat, libocmarkdown, libocmarkdowngtk, libocsqlite
  subdir('ollmapp')         # Primary application - depends on all libraries
  if get_option('examples')
    subdir('examples')          # Depends on all libraries
  endif
  if get_option('tests')
    if not get_option('examples')
      error('The tests option requires examples=true')
    endif
    subdir('tests')             # Test suite - depends on examples
  endif
endif

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
if android_shell_poc
  executables_info = [
    ['ollmchat-android-shell-poc', 'ollmapp/ollmchat-android-shell-poc'],
  ]
elif android_poc_opt and host_machine.system() == 'android'
  executables_info = [
    ['ollmchat-android-poc', 'ollmapp/ollmchat-android-poc'],
  ]
else
  executables_info = [
    ['ollmchat.bin', 'ollmapp/ollmchat'],  # Wrapper for testing ollama chat with latest code
    ['ollmchat-cli', 'ollmapp/ollmchat-cli'],  # CLI tool for testing agent tools
    ['oc-test-cli', 'examples/oc-test-cli'],
    ['oc-test-pull', 'examples/oc-test-pull'],
    ['oc-test-fetch', 'examples/oc-test-fetch'],
    ['oc-test-loop', 'examples/oc-test-loop'],
    ['oc-test-files', 'examples/oc-test-files'],
    ['oc-test-bubble', 'examples/oc-test-bubble'],
    ['oc-test-skill-agent', 'examples/oc-test-skill-agent'],
    ['oc-test-gtkmd', 'examples/oc-test-gtkmd'],
    ['oc-markdown-test', 'examples/oc-markdown-test'],
    ['oc-markdown-doc-test', 'examples/oc-markdown-doc-test'],
    ['oc-html2md', 'examples/oc-html2md'],
    ['oc-test-ollamaweb', 'examples/oc-test-ollamaweb'],
    ['oc-md2html', 'examples/oc-md2html'],
    ['oc-diff', 'examples/oc-diff'],
    ['oc-migrate-editors', 'examples/oc-migrate-editors'],
    ['oc-vector-index', 'examples/oc-vector-index'],
    ['oc-vector-search', 'examples/oc-vector-search']
  ]
endif

if local_gguf_enabled
  executables_info += [
    ['oc-local-gguf-embed', 'examples/oc-local-gguf-embed'],
    ['oc-local-gguf-chat', 'examples/oc-local-gguf-chat'],
  ]
endif
if get_option('android_poc')
  executables_info += [
    ['ollmchat-android-poc', 'ollmapp/ollmchat-android-poc'],
  ]
endif

# Library paths for LD_LIBRARY_PATH
lib_path = ':'.join([
  meson.current_build_dir() / 'libocsqlite',
  meson.current_build_dir() / 'libocrpc',
  meson.current_build_dir() / 'libocmarkdown',
  meson.current_build_dir() / 'libollamaweb',
  meson.current_build_dir() / 'libocmarkdowngtk',
  meson.current_build_dir() / 'libocfiles',
  meson.current_build_dir() / 'liboccoder',
  meson.current_build_dir() / 'libollmchat',
  meson.current_build_dir() / 'libollmchatgtk',
  meson.current_build_dir() / 'libocvector',
  meson.current_build_dir() / 'liboctools',
  meson.current_build_dir() / 'libocmcp'
])

if local_gguf_enabled
  dpkg_arch = run_command('dpkg-architecture', '-qDEB_HOST_MULTIARCH', check: false)
  if dpkg_arch.returncode() == 0
    multiarch = dpkg_arch.stdout().strip()
    if multiarch != ''
      lib_path = lib_path + ':/usr/lib/' + multiarch + '/llama'
    endif
  endif
endif

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

if get_option('docs') and not android_cross_build
  subdir('docs')             # Depends on all source files
endif

# Post-install script to update icon cache and desktop database when the host
# tools are available. Minimal CI/package builders may not install both.
if not android_cross_build
  gnome.post_install(
    gtk_update_icon_cache: find_program('gtk-update-icon-cache', required: false).found(),
    update_desktop_database: find_program('update-desktop-database', required: false).found()
  )
endif
