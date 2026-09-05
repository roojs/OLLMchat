# Resolve bundled-dependency roots once. sqgipkg should pass -Dsysroot=... (and
# -Dwindows_prefix=... on Windows). Empty options mean a normal native build
# (Debian packages, local dev) using pkg-config and the host toolchain.
cc = meson.get_compiler('c')

bundle_sysroot = get_option('sysroot')
if bundle_sysroot == ''
  bundle_sysroot = run_command('sh', '-c', 'printf %s "$SQGI_LINUX_SYSROOT"', check: false).stdout().strip()
endif

bundle_windows_prefix = get_option('windows_prefix')
if bundle_windows_prefix == ''
  bundle_windows_prefix = run_command('sh', '-c', 'printf %s "$SQGI_WINDOWS_SYSROOT_PREFIX"', check: false).stdout().strip()
endif

bundle_triplet = get_option('sysroot_triplet')
if bundle_triplet == ''
  bundle_triplet = run_command('sh', '-c', 'printf %s "$SQGI_LINUX_TRIPLET"', check: false).stdout().strip()
endif

bundle_using_sysroot = bundle_sysroot != '' or bundle_windows_prefix != ''

# Library search dirs and include flags for bundled deps.
bundle_lib_dirs = []
bundle_include_args = []
if bundle_sysroot != ''
  bundle_lib_dirs += bundle_sysroot / 'usr' / 'lib'
  bundle_include_args += '-I' + bundle_sysroot / 'usr' / 'include'
  if bundle_triplet != ''
    bundle_lib_dirs += bundle_sysroot / 'usr' / 'lib' / bundle_triplet
  endif
endif
if bundle_windows_prefix != ''
  bundle_lib_dirs += bundle_windows_prefix / 'lib'
  bundle_include_args += '-I' + bundle_windows_prefix / 'include'
endif

openblas_dirs = []
if bundle_sysroot != '' and bundle_triplet != ''
  openblas_dirs += bundle_sysroot / 'usr' / 'lib' / bundle_triplet / 'openblas-pthread'
endif
if bundle_windows_prefix != ''
  openblas_dirs += bundle_windows_prefix / 'lib'
endif

# --- tree-sitter ---
if bundle_using_sysroot
  tree_sitter_dep = declare_dependency(
    dependencies: [cc.find_library('tree-sitter', dirs: bundle_lib_dirs, required: true)],
    compile_args: bundle_include_args,
  )
else
  tree_sitter_dep = dependency('tree-sitter', required: true)
endif

# --- FAISS (libocvector2 / ollmfilesd) ---
if bundle_using_sysroot
  faiss_lib = cc.find_library('faiss', dirs: bundle_lib_dirs, required: true)
  faiss_dep = declare_dependency(
    dependencies: [faiss_lib],
    compile_args: bundle_include_args,
  )
else
  faiss_dep = declare_dependency(
    dependencies: [cc.find_library('faiss', required: true)],
  )
endif

# --- BLAS/LAPACK link flags for libocvector2 (not passed through Vala deps) ---
blas_dep = dependency('blas', required: false)
lapack_dep = dependency('lapack', required: false)
openblas_lib = cc.find_library('openblas', dirs: openblas_dirs, required: false)
lapack_openblas_lib = cc.find_library('lapack', dirs: openblas_dirs, required: false)
ocvector_link_libs = ['-lgomp']
using_openblas_dirs = false
if bundle_using_sysroot and openblas_lib.found()
  using_openblas_dirs = true
  ocvector_link_libs += ['-lopenblas']
  if lapack_openblas_lib.found()
    ocvector_link_libs += ['-llapack']
  endif
elif blas_dep.found()
  ocvector_link_libs += ['-lblas']
  if lapack_dep.found()
    ocvector_link_libs += ['-llapack']
  else
    cc.find_library('lapack', required: true)
    ocvector_link_libs += ['-llapack']
  endif
elif openblas_lib.found()
  using_openblas_dirs = true
  ocvector_link_libs += ['-lopenblas']
  if lapack_openblas_lib.found()
    ocvector_link_libs += ['-llapack']
  endif
else
  cc.find_library('blas', required: true)
  ocvector_link_libs += ['-lblas']
  cc.find_library('lapack', required: true)
  ocvector_link_libs += ['-llapack']
endif
ocvector_link_dirs = []
if using_openblas_dirs
  foreach d : openblas_dirs
    ocvector_link_dirs += ['-L' + d, '-Wl,-rpath-link,' + d]
  endforeach
endif
ocvector_link_dep = declare_dependency(link_args: ocvector_link_dirs + ocvector_link_libs)

# --- libseccomp (libocbwrap, Linux only) ---
# Do not pass dependency('libseccomp') into Vala targets: Meson would add
# --pkg libseccomp, and there is no system vapi (we use vapi/seccomp.vapi).
# pkg-config is still required for C flags: openSUSE installs seccomp.h under
# /usr/include/libseccomp/, not /usr/include/.
if host_machine.system() != 'windows'
  if bundle_using_sysroot and bundle_lib_dirs.length() > 0
    libseccomp_dep = declare_dependency(
      dependencies: [cc.find_library('seccomp', dirs: bundle_lib_dirs, required: true)],
      compile_args: bundle_include_args,
    )
  else
    # Meson 1.11 still adds --pkg libseccomp from partial_dependency();
    # valac then looks for a system vapi that does not exist. C library only,
    # same as the sysroot branch (in-tree vapi/seccomp.vapi is --pkg=seccomp).
    libseccomp_pc = dependency('libseccomp', required: true)
    libseccomp_inc = libseccomp_pc.get_variable(
      pkgconfig: 'includedir',
      default_value: '',
    )
    libseccomp_cflags = []
    if libseccomp_inc != ''
      libseccomp_cflags += ['-I' + libseccomp_inc]
    endif
    libseccomp_dep = declare_dependency(
      dependencies: [cc.find_library('seccomp', required: true)],
      compile_args: libseccomp_cflags,
    )
  endif
endif

# --- WebKitGTK with WebDriver interactions (libocwebkit Linux) ---
# Consumer contract: webkitgtk-automation docs/consuming.md — probe the .so
# behind each pkg-config module; prefer parallel webdriver, else stock (Fedora).
# Do not pass the chosen Dependency into Vala targets when the module is
# webkitgtk-6.0-webdriver — Meson would add --pkg=webkitgtk-6.0-webdriver (no
# such Vala module). Vala stays --pkg=webkitgtk-6.0 (+ optional
# --pkg=webkitgtk-webdriver when the .so exports navigator-policy). Link C only.
webkit_have_navigator_policy = false
if host_machine.system() == 'linux'
  webkit_interactions_check = meson.project_source_root() / 'scripts' / 'meson' / 'check-webkit-interactions.sh'
  webkit_pc_raw = disabler()
  webkit_pc_used = ''
  foreach pc : ['webkitgtk-6.0-webdriver', 'webkitgtk-6.0']
    _dep = dependency(pc, required: false)
    if _dep.found() and run_command(webkit_interactions_check, pc, check: false).returncode() == 0
      webkit_pc_raw = _dep
      webkit_pc_used = pc
      break
    endif
  endforeach
  if not webkit_pc_raw.found()
    error('No WebKitGTK with WebDriver interactions found. '
      + 'On Ubuntu/Debian install libwebkitgtk-6.0-webdriver-dev.')
  endif
  message('WebKitGTK for automation: @0@'.format(webkit_pc_used))

  # Optional #165269 hide API — same .so probe, not distro guessing.
  if run_command(webkit_interactions_check, webkit_pc_used, 'navigator-policy', check: false).returncode() == 0
    webkit_have_navigator_policy = true
  endif
  message('WebKitGTK navigator.webdriver policy: @0@'.format(
    webkit_have_navigator_policy.to_string()))

  webkit_webdriver_libdir = webkit_pc_raw.get_variable(pkgconfig: 'libdir')
  webkit_webdriver_inc = webkit_pc_raw.get_variable(pkgconfig: 'includedir')
  webkit_webdriver_cflags = [
    '-I' + join_paths(webkit_webdriver_inc, 'webkitgtk-6.0'),
  ]
  if webkit_have_navigator_policy
    webkit_webdriver_cflags += [
      '-I' + join_paths(webkit_webdriver_inc, 'webkitgtk-webdriver-6.0'),
    ]
  endif
  if webkit_pc_used == 'webkitgtk-6.0-webdriver'
    # Versioned .so only (no unversioned .so in -dev); same as .pc Libs -l:.
    webkit_webdriver_dep = declare_dependency(
      dependencies: [dependency('javascriptcoregtk-6.0')],
      compile_args: webkit_webdriver_cflags,
      link_args: [
        join_paths(webkit_webdriver_libdir, 'libwebkitgtk-6.0-webdriver.so.4'),
      ],
    )
  else
    # Stock GTK4 WebKit already has interactions (Fedora etc.): safe for Vala --pkg.
    webkit_webdriver_dep = declare_dependency(
      dependencies: [webkit_pc_raw],
      compile_args: webkit_webdriver_cflags,
    )
  endif
endif
