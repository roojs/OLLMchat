# Local GGUF / libllama PoC executables (test-only; not linked into libollmchat
# and not built for packages where -Dtests=false or -Dlocal_gguf=disabled).

local_gguf_opt = get_option('local_gguf')
local_gguf_enabled = false
local_gguf_deps = []
local_gguf_rpath_dirs = [
  meson.project_build_root() / 'libocsqlite',
  meson.project_build_root() / 'libocmarkdown',
  meson.project_build_root() / 'libollamaweb',
  meson.project_build_root() / 'libocrpc',
  meson.project_build_root() / 'libollmchat',
]

# Debian libllama is under /usr/lib/<multiarch>/llama. Meson run_command()
# still requires the binary to exist even with check: false — probe first so
# Fedora/openSUSE (pkg-config llama, no dpkg) can configure.
debian_llama_libdir = ''
dpkg_architecture = find_program('dpkg-architecture', required: false)
if dpkg_architecture.found()
  dpkg_arch = run_command(dpkg_architecture, '-qDEB_HOST_MULTIARCH', check: false)
  if dpkg_arch.returncode() == 0
    multiarch = dpkg_arch.stdout().strip()
    if multiarch != ''
      debian_llama_libdir = '/usr/lib' / multiarch / 'llama'
    endif
  endif
endif

if not local_gguf_opt.disabled()
  llama_dep = dependency('llama', required: false)
  if llama_dep.found() and cc.has_header('llama.h', dependencies: llama_dep)
    local_gguf_deps += llama_dep
    local_gguf_enabled = true
  else
    private_llama_dirs = []
    private_llama_link_args = []
    private_llama_compile_args = []
    private_llama_header_found = false

    if debian_llama_libdir != ''
      private_llama_dirs += debian_llama_libdir
      private_llama_link_args += '-Wl,-rpath,' + debian_llama_libdir
    endif

    if cc.has_header('llama.h', required: false)
      private_llama_compile_args = []
      private_llama_header_found = true
    elif cc.has_header('llama.h', args: ['-I/usr/include/llama'], required: false)
      private_llama_compile_args = ['-I/usr/include/llama']
      private_llama_header_found = true
    endif

    llama_private_lib = cc.find_library('llama',
      dirs: private_llama_dirs,
      required: false
    )
    if llama_private_lib.found() and private_llama_header_found
      local_gguf_deps += declare_dependency(
        dependencies: llama_private_lib,
        compile_args: private_llama_compile_args,
        link_args: private_llama_link_args
      )
      local_gguf_enabled = true
    endif
  endif

  if not local_gguf_enabled and local_gguf_opt.enabled()
    error('local_gguf=enabled requires libllama headers and library')
  endif
endif

if local_gguf_enabled
  if debian_llama_libdir != ''
    local_gguf_rpath_dirs += debian_llama_libdir
  endif
  local_gguf_build_rpath = ':'.join(local_gguf_rpath_dirs)

  local_gguf_common_deps = [
    dependency('gee-0.8'),
    dependency('gio-2.0'),
    dependency('glib-2.0'),
    dependency('gobject-2.0'),
    dependency('json-glib-1.0'),
    dependency('libsoup-3.0'),
    valac.find_library('posix'),
    ocsqlite_vapi_dep,
    ocmarkdown_vapi_dep,
    ocrpc_vapi_dep,
    ollamaweb_vapi_dep,
    ollmchat_vapi_dep,
  ] + local_gguf_deps

  local_gguf_include_dirs = [
    include_directories('../../libollmchat'),
    include_directories('../../libollamaweb'),
  ]

  local_gguf_vala_args = [
    '--pkg=sqlite3',
    '--pkg=ocsqlite',
    '--pkg=ocmarkdown',
    '--pkg=ocrpc',
    '--pkg=ollamaweb',
    '--pkg=ollmchat',
    '--pkg=llama',
    '--vapidir', meson.project_build_root() / 'libocsqlite',
    '--vapidir', meson.project_build_root() / 'libocmarkdown',
    '--vapidir', meson.project_build_root() / 'libocrpc',
    '--vapidir', meson.project_build_root() / 'libollamaweb',
    '--vapidir', meson.project_build_root() / 'libollmchat',
  ]

  oc_local_gguf_chat = executable('oc-local-gguf-chat',
    sources: [
      'GGUF.vala',
      'Thread.vala',
      'ChatCompletions.vala',
      'oc-local-gguf-chat.vala',
    ],
    dependencies: local_gguf_common_deps,
    link_with: [ollmchat_base_lib],
    include_directories: local_gguf_include_dirs,
    build_rpath: local_gguf_build_rpath,
    vala_args: local_gguf_vala_args,
    install: false,
  )

  oc_local_gguf_embed = executable('oc-local-gguf-embed',
    sources: [
      'GGUF.vala',
      'Thread.vala',
      'Embeddings.vala',
      'oc-local-gguf-embed.vala',
    ],
    dependencies: local_gguf_common_deps,
    link_with: [ollmchat_base_lib],
    include_directories: local_gguf_include_dirs,
    build_rpath: local_gguf_build_rpath,
    vala_args: local_gguf_vala_args,
    install: false,
  )

  message('local_gguf enabled: building tests/local-gguf PoC executables')
else
  message('local_gguf disabled: skipping tests/local-gguf PoC executables')
endif
