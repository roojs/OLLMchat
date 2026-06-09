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

# --- FAISS (libocvector) ---
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

# --- BLAS/LAPACK link flags for libocvector (not passed through Vala deps) ---
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

# --- libseccomp (libocfiles, Linux only) ---
if host_machine.system() != 'windows'
  if bundle_using_sysroot and bundle_lib_dirs.length() > 0
    libseccomp_dep = cc.find_library('seccomp', dirs: bundle_lib_dirs, required: true)
  else
    libseccomp_dep = cc.find_library('seccomp', required: true)
  endif
endif
