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
android_cross_build = host_machine.system() == 'android' and (
  android_shell_poc or android_poc_opt
)

android_poc_count = 0
if android_shell_poc
  android_poc_count += 1
endif
if android_poc_opt
  android_poc_count += 1
endif
if android_poc_count > 1
  error('Only one of android_shell_poc, android_poc may be set')
endif

if not get_option('v2testing')
  error('Shipping v1 (v2testing=false) was removed. Use the default build (v2testing=true).')
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
gee_vapi_dir = meson.project_source_root() / 'subprojects/libgee-0.20.8/gee'

if android_cross_build
  # GIO TLS for libsoup HTTPS: build OpenSSL + glib-networking GIO modules.
  # TLS modules are copied into APK assets (see install_gio_modules_to_assets
  # in scripts/android/build-pixiewood-apk.sh); main() calls
  # ollmapp_configure_android_gio_tls_modules() before any network I/O.
  subproject('glib-networking')

  # GObject introspection is disabled on Android, so Meson does not attach
  # --pkg lines for C-library deps to library() targets. Bundled vapis under
  # vapi/ still need explicit --pkg flags at compile time.
  # gee-0.8 is omitted here: Meson already passes gee-0.8.vapi as an input to
  # library() and executable() compiles via dependency('gee-0.8'). Adding
  # --pkg=gee-0.8 here duplicates the vapi ("Gee already contains definition")
  # or fails lookup ("Package gee-0.8 not found"). See docs/android-build.md
  # (Vala / gee-0.8). Custom vapi targets are the exception — they need
  # --vapidir subprojects/libgee-0.20.8/gee plus --pkg=gee-0.8 in their
  # custom_target command, not on executables.
  add_project_arguments([
    '--pkg=json-glib-1.0',
    '--pkg=libsoup-3.0',
    '--pkg=libxml-2.0',
  ], language: 'vala')
endif

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

# libocvector2.so is the daemon FAISS lib; app uses liboctools/CodebaseSearch (RPC).
ocfiles_lib = get_option('v2testing') ? 'ocfiles2' : 'ocfiles'
occoder_lib = get_option('v2testing') ? 'occoder2' : 'occoder'
octools_lib = get_option('v2testing') ? 'octools2' : 'octools'
ocmcp_lib = get_option('v2testing') ? 'ocmcp2' : 'ocmcp'

# Build libraries in dependency order
if android_shell_poc
  subdir('ollmapp')         # Minimal Android APK shell target only
elif android_poc_opt and host_machine.system() == 'android'
  subdir('libocmarkdown')
  subdir('libocmarkdowngtk')
  subdir('libocsqlite')
  subdir('libollamaweb')
  subdir('libollmchat')
  subdir('libollmchatgtk')
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
  subdir('libocbwrap')     # bwrap / overlay / seccomp — full on Linux, stubs elsewhere
  subdir('ollmfilesd')       # Headless file daemon — Unix socket on Unix, TCP on Windows
  subdir('libocmcp')         # Depends on libollmchat, libocfiles
  subdir('liboctools')       # Depends on libollmchat, libocfiles
  subdir('liboccoder')       # Depends on libocsqlite, libocfiles, libollmchat
  subdir('libollmchatgtk')   # Depends on libollmchat, libocmarkdown, libocmarkdowngtk, libocsqlite
  subdir('ollmapp')         # Primary application - depends on all libraries
  if get_option('examples')
    subdir('examples')          # RPC vector CLIs and minimal repros only
  endif
  if get_option('tests')
    subdir('tests')             # RPC tests always; legacy example tests skip if target missing
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
@OLLMFILESD_EXPORT@

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
  ]
  if get_option('v2testing')
    executables_info += [['ollmchat-cli', 'ollmapp/ollmchat-cli']]  # V2 only
  endif
  if get_option('examples')
    executables_info += [
      ['oc-vector-index', 'examples/oc-vector-index'],
      ['oc-vector-search', 'examples/oc-vector-search'],
    ]
  endif
endif
if get_option('android_poc') and host_machine.system() != 'android'
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

if get_option('v2testing')
  ollmfilesd_export = 'export OLLM_OLLMFILESD="' + meson.current_build_dir() / 'ollmfilesd' / 'ollmfilesd' + '"'
else
  ollmfilesd_export = ''
endif

# Create wrapper scripts in top-level build directory
foreach exe_info : executables_info
  exe_name = exe_info[0]
  exe_path = exe_info[1]
  wrapper_content = wrapper_template.replace('@EXECUTABLE@', exe_name)
  wrapper_content = wrapper_content.replace('@EXECUTABLE_PATH@', meson.current_build_dir() / exe_path)
  wrapper_content = wrapper_content.replace('@LIB_PATH@', lib_path)
  wrapper_content = wrapper_content.replace('@OLLMFILESD_EXPORT@', ollmfilesd_export)
  
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
