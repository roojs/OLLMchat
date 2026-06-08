# Build ocfiles library (libocfiles.so) - depends on libocsqlite
# Provides file and project management without GTK/git dependencies

# Dependencies for ocfiles library
valac = meson.get_compiler('vala')
cc = meson.get_compiler('c')
is_windows = host_machine.system() == 'windows'
# Find tree-sitter library (C library for parsing)
tree_sitter_lib = dependency('tree-sitter', required: false)
if not tree_sitter_lib.found()
  linux_sysroot = run_command('sh', '-c', 'printf %s "$SQGI_LINUX_SYSROOT"', check: false).stdout().strip()
  linux_triplet = run_command('sh', '-c', 'printf %s "$SQGI_LINUX_TRIPLET"', check: false).stdout().strip()
  windows_sysroot_prefix = run_command('sh', '-c', 'printf %s "$SQGI_WINDOWS_SYSROOT_PREFIX"', check: false).stdout().strip()
  tree_sitter_dirs = []
  tree_sitter_compile_args = []
  if linux_sysroot != '' and linux_triplet != ''
    tree_sitter_dirs += linux_sysroot / 'usr' / 'lib' / linux_triplet
    tree_sitter_compile_args += '-I' + linux_sysroot / 'usr' / 'include'
  endif
  if windows_sysroot_prefix != ''
    tree_sitter_dirs += windows_sysroot_prefix / 'lib'
    tree_sitter_compile_args += '-I' + windows_sysroot_prefix / 'include'
  endif
  tree_sitter_lib = declare_dependency(
    dependencies: [cc.find_library('tree-sitter', dirs: tree_sitter_dirs, required: true)],
    compile_args: tree_sitter_compile_args,
  )
endif
ocfiles_deps = [
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('gmodule-2.0'),  # GModule for dynamic library loading
  dependency('json-glib-1.0'),  # Required for ProjectMigrate (JSON parsing)
  dependency('sqlite3'),
  valac.find_library('posix'),
  tree_sitter_lib,  # Tree-sitter C library (required - TreeBase uses TreeSitter API)
]

ocfiles_vapi_pkgs = [
  '--pkg=sqlite3',
  '--pkg=json-glib-1.0',  # Required for ProjectMigrate (JSON parsing)
  '--pkg=gmodule-2.0',  # GModule for dynamic library loading (required for TreeBase)
  '--pkg=tree-sitter',  # Tree-sitter via vapi (required for TreeBase)
  '--pkg=ocsqlite',
]

ocfiles_vapi_gen_pkgs = [
  '--pkg', 'posix',
  '--pkg', 'sqlite3',
  '--pkg', 'json-glib-1.0',  # Required for ProjectMigrate (JSON parsing)
  '--pkg', 'gmodule-2.0',  # GModule for dynamic library loading (required for TreeBase)
  '--pkg', 'tree-sitter',  # Tree-sitter via vapi (required for TreeBase)
  '--pkg', 'ocsqlite',
  '--pkg', 'gobject-2.0',
  '--pkg', 'glib-2.0',
  '--pkg', 'gio-2.0',
  '--pkg', 'gee-0.8',
]

ocfiles_extra_sources = []
sandbox_src = files(['Sandbox/BubbleWindows.vala'])
if not is_windows
  libseccomp_lib = cc.find_library('seccomp', required: false)
  if not libseccomp_lib.found()
    linux_sysroot = run_command('sh', '-c', 'printf %s "$SQGI_LINUX_SYSROOT"', check: false).stdout().strip()
    linux_triplet = run_command('sh', '-c', 'printf %s "$SQGI_LINUX_TRIPLET"', check: false).stdout().strip()
    seccomp_dirs = []
    if linux_sysroot != '' and linux_triplet != ''
      seccomp_dirs += linux_sysroot / 'usr' / 'lib' / linux_triplet
    endif
    libseccomp_lib = cc.find_library('seccomp', dirs: seccomp_dirs, required: true)
  endif
  seccomp_vapi = valac.find_library(
    'seccomp',
    dirs: meson.current_source_dir() / '../vapi',
    required: true,
  )
  ocfiles_deps += [
    dependency('gio-unix-2.0'),
    valac.find_library('linux'),
    seccomp_vapi,
    libseccomp_lib,
  ]
  ocfiles_vapi_pkgs += [
    '--pkg=seccomp',
    '--pkg=linux',
    '--pkg=gio-unix-2.0',
  ]
  ocfiles_vapi_gen_pkgs += [
    '--pkg', 'seccomp',
    '--pkg', 'linux',
    '--pkg', 'gio-unix-2.0',
  ]
  ocfiles_extra_sources += files(meson.current_source_dir() / '../vapi/seccomp-fd-pass.c')
  sandbox_src = files([
    'Sandbox/Bubble.vala',
    'Sandbox/RunSeccomp.vala',
  ])
endif

ocfiles_src = files([
  'BufferProviderBase.vala',
  'FileBuffer.vala',  # Must come before File.vala (File uses FileBuffer)
  'FileChange.vala',
  'DummyFileBuffer.vala',
  'FileBase.vala',
  'FileHistory.vala',  # Uses FileBase
  'File.vala',
  'FileAlias.vala',
  'Folder.vala',
  'Sandbox/Scan.vala',
  'Sandbox/Overlay.vala',
  'FolderFiles.vala',
  'GitProviderBase.vala',
  'ProjectFile.vala',
  'ProjectFiles.vala',
  'ReviewFiles.vala',  # Uses ProjectFiles
  'ProjectList.vala',
  'ProjectManager.vala',
  'DeleteManager.vala',  # Uses ProjectManager
  'ProjectMigrate.vala',
  'TreeBase.vala',  # Tree-sitter base class
  'Tree.vala',  # Tree-sitter AST path lookup class
  'Diff/Patch.vala',
  'Diff/PatchApplier.vala',
  'Diff/Differ.vala',
  'SQT/VectorMetadata.vala',  # Vector metadata (SQL) - OLLMfiles.SQT namespace
])
ocfiles_src += sandbox_src

# Build rpath for libraries to find each other in build directory
lib_build_rpath = ':'.join([
  meson.current_build_dir(),
  meson.current_build_dir() / '..' / 'libocsqlite',
])

ocfiles_base_lib = library('ocfiles',
  dependencies: [ocfiles_deps, ocsqlite_vapi_dep],
  sources: ocfiles_src + ocfiles_extra_sources,
  vala_header: 'ocfiles.h',
  vala_vapi: 'ocfiles-meson.vapi',  # Use different name so our custom_target can use 'ocfiles.vapi'
  build_rpath: lib_build_rpath,
  include_directories: [
    include_directories('..' / 'vapi'),
  ],
  vala_args: ocfiles_vapi_pkgs + [
    # Put build directories FIRST so we use local VAPIs instead of installed ones
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_source_dir() / '../vapi',  # For tree-sitter.vapi and seccomp
    '--vapidir', '/usr/share/vala/vapi'  # System VAPI directory (last, so local takes priority)
  ],
  install: true
)

# Manually generate ocfiles.vapi with correct command line order
ocfiles_vapi = custom_target('ocfiles-vapi',
  output: 'ocfiles.vapi',
  input: ocfiles_src,
  command: [
    valac_exe,
    '-C', '--debug',
    '--target-glib=auto',
    # Put build directories FIRST so we use local VAPIs instead of installed ones
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir(),
    '--vapidir', meson.current_source_dir() / '../vapi',  # For tree-sitter.vapi
    '--vapidir', meson.current_source_dir() / '../../vapi',
    '--vapidir', '/usr/share/vala/vapi',  # System VAPI directory (last, so local takes priority)
  ] + ocfiles_vapi_gen_pkgs + [
    '--library', 'ocfiles',
    '--header', meson.current_build_dir() / 'ocfiles.h',  # Use header from library
    '--vapi', '@OUTPUT@',
    '@INPUT@'
  ],
  depends: [ocfiles_base_lib],  # Ensure library is built first (so header exists)
  build_by_default: true,
  install: true,
  install_dir: get_option('datadir') / 'vala' / 'vapi'
)

# Create dependency for other libraries to use
# Use link_args instead of link_with to prevent meson from auto-including ocfiles-meson.vapi
ocfiles_vapi_dep = declare_dependency(
  link_args: ['-L' + meson.current_build_dir(), '-locfiles'],
  sources: [ocfiles_vapi[0]],  # Include VAPI file to ensure it's built first
  dependencies: [ocsqlite_vapi_dep, ocfiles_deps]
)

# GObject Introspection for ocfiles library
ocfiles_gir = gnome.generate_gir(ocfiles_base_lib,
  namespace: 'OLLMfiles',
  nsversion: '1.0',
  identifier_prefix: 'OLLMfiles',
  symbol_prefix: 'ollmfiles',
  link_with: [ocsqlite_base_lib],
  dependencies: [dependency('sqlite3')],
  extra_args: [
    '--extra-library=ocsqlite',
    '--accept-unprefixed'
  ],
  includes: ['GObject-2.0', 'Gio-2.0', ocsqlite_gir[0]],
  install: true,
  fatal_warnings: false
)
