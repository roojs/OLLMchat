# Build ocfiles library (libocfiles.so) - depends on libocsqlite
# Provides file and project management without GTK/git dependencies

# Dependencies for ocfiles library
valac = meson.get_compiler('vala')
cc = meson.get_compiler('c')
is_windows = host_machine.system() == 'windows'
# tree-sitter: resolved in config/meson.build
ocfiles_deps = [
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('gmodule-2.0'),  # GModule for dynamic library loading
  dependency('json-glib-1.0'),  # Required for ProjectMigrate (JSON parsing)
  dependency('sqlite3'),
  valac.find_library('posix'),
  tree_sitter_dep,
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
sandbox_src = files()
if not get_option('v2testing')
  sandbox_src = files(['Sandbox/BubbleWindows.vala'])
  if not is_windows
    # libseccomp: resolved in config/meson.build
    seccomp_vapi = valac.find_library(
      'seccomp',
      dirs: meson.current_source_dir() / '../vapi',
      required: true,
    )
    ocfiles_deps += [
      dependency('gio-unix-2.0'),
      valac.find_library('linux'),
      seccomp_vapi,
      libseccomp_dep,
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
endif

if get_option('v2testing')
  ocfiles_src = files([
    'BufferProviderBase.vala',
    'V2/FileBuffer.vala',
    'DummyFileBuffer.vala',
    'FileChange.vala',
    'V2/FileHistory.vala',
    'V2/FileAlias.vala',
    'V2/FileWithHistory.vala',
    'GitProviderBase.vala',
    'Copyable.vala',
    meson.current_source_dir() / '../ollmfilesd/CallParam.vala',
    'Diff/Patch.vala',
    'Diff/PatchApplier.vala',
    'Diff/Differ.vala',
    'SQT/VectorMetadata.vala',
    'V2/FileBase.vala',
    'V2/File.vala',
    'V2/Folder.vala',
    'V2/FolderFiles.vala',
    'V2/ProjectFile.vala',
    'V2/ProjectFiles.vala',
    'V2/ReviewFiles.vala',
    'V2/ProjectList.vala',
    'V2/ProjectManager.vala',
    'V2/DeleteManager.vala',
    'V2/TreeBase.vala',
    'V2/Tree.vala',
  ])
else
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
endif

# Build rpath for libraries to find each other in build directory
lib_build_rpath = ':'.join([
  meson.current_build_dir(),
  meson.current_build_dir() / '..' / 'libocsqlite',
  meson.current_build_dir() / '..' / 'libocrpc',
])

ocfiles_lib_deps = [ocfiles_deps, ocrpc_vapi_dep, ocsqlite_vapi_dep]

ocfiles_base_lib = library(ocfiles_lib,
  dependencies: ocfiles_lib_deps,
  sources: ocfiles_src + ocfiles_extra_sources,
  vala_header: 'ocfiles.h',
  vala_vapi: 'ocfiles-meson.vapi',  # Use different name so our custom_target can use 'ocfiles.vapi'
  vala_gir: get_option('v2testing') ? [] : 'OLLMfiles-1.0.gir',
  build_rpath: lib_build_rpath,
  include_directories: [
    include_directories('..' / 'vapi'),
  ],
  vala_args: ocfiles_vapi_pkgs + ['--pkg=ocrpc'] + strcasestr_vala_args + [
    # Put build directories FIRST so we use local VAPIs instead of installed ones
    '--vapidir', meson.current_build_dir() / '..' / 'libocrpc',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_source_dir() / '../vapi',  # For tree-sitter.vapi and seccomp
    '--vapidir', '/usr/share/vala/vapi',  # System VAPI directory (last, so local takes priority)
    '--girdir', meson.current_build_dir() / '..' / 'libocsqlite',
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
    '--vapidir', meson.current_build_dir() / '..' / 'libocrpc',
    '--vapidir', meson.current_build_dir() / '..' / 'libocsqlite',
    '--vapidir', meson.current_build_dir(),
    '--vapidir', meson.current_source_dir() / '../vapi',  # For tree-sitter.vapi
    '--vapidir', meson.current_source_dir() / '../../vapi',
    '--vapidir', '/usr/share/vala/vapi',  # System VAPI directory (last, so local takes priority)
  ] + ['--pkg', 'ocrpc'] + ocfiles_vapi_gen_pkgs + strcasestr_vala_args + [
    '--library', ocfiles_lib,
    '--header', meson.current_build_dir() / 'ocfiles.h',  # Use header from library
    '--vapi', '@OUTPUT@',
    '@INPUT@'
  ],
  depends: [ocfiles_base_lib, ocrpc_vapi],
  build_by_default: true,
  install: true,
  install_dir: get_option('datadir') / 'vala' / 'vapi'
)

ocfiles_vapi_dep_deps = [ocrpc_vapi_dep, ocsqlite_vapi_dep, ocfiles_deps]

# Create dependency for other libraries to use
# Use link_args instead of link_with to prevent meson from auto-including ocfiles-meson.vapi
ocfiles_vapi_dep = declare_dependency(
  link_args: ['-L' + meson.current_build_dir(), '-l' + ocfiles_lib],
  sources: [ocfiles_vapi[0]],  # Include VAPI file to ensure it's built first
  dependencies: ocfiles_vapi_dep_deps
)

if not get_option('v2testing')
  ocfiles_gir_file = meson.current_build_dir() / 'OLLMfiles-1.0.gir'
  custom_target('ocfiles-typelib',
    output: 'OLLMfiles-1.0.typelib',
    command: [
      g_ir_compiler, ocfiles_gir_file, '--output', '@OUTPUT@',
      '--includedir', meson.current_build_dir() / '..' / 'libocsqlite',
      '--includedir', '/usr/share/gir-1.0',
    ],
    depends: ocfiles_base_lib,
    build_by_default: true,
    install: true,
    install_dir: get_option('libdir') / 'girepository-1.0',
  )
  meson.add_install_script(
    'sh', '-c',
    'install -Dm644 "' + ocfiles_gir_file + '" "$DESTDIR$MESON_INSTALL_PREFIX/share/gir-1.0/OLLMfiles-1.0.gir"',
  )
endif
