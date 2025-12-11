"""Helper functions for Vala VAPI generation in Meson builds."""

def generate_vapi_command(lib_name, extra_pkgs=None, extra_vapidirs=None):
    """
    Generate the command array for creating a VAPI file.
    
    Args:
        lib_name: Name of the library (e.g., 'ocsqlite', 'occoder')
        extra_pkgs: List of additional packages beyond the standard ones
        extra_vapidirs: List of additional vapidir paths beyond the standard ones
    
    Returns:
        List of command arguments for valac
    """
    # Standard packages that are always included
    standard_pkgs = ['posix', 'gobject-2.0', 'glib-2.0', 'gio-2.0', 'gee-0.8']
    
    # Standard vapidirs (will be set in meson.build)
    standard_vapidirs = []
    
    # Combine standard and extra packages
    all_pkgs = standard_pkgs
    if extra_pkgs:
        all_pkgs = all_pkgs + extra_pkgs
    
    # Build command array
    cmd = [
        '@valac_exe@',
        '-C', '--debug',
        '--target-glib=auto',
    ]
    
    # Add standard vapidirs (these will be replaced in meson.build)
    cmd += ['--vapidir', '@vapidir_src@']
    cmd += ['--vapidir', '@vapidir_src_parent@']
    cmd += ['--vapidir', '@vapidir_build@']
    
    # Add extra vapidirs
    if extra_vapidirs:
        for vapidir in extra_vapidirs:
            cmd += ['--vapidir', vapidir]
    
    # Add all packages
    for pkg in all_pkgs:
        cmd += ['--pkg', pkg]
    
    # Add library-specific arguments
    cmd += ['--library', lib_name]
    cmd += ['--header', '@header_path@']
    cmd += ['--vapi', '@OUTPUT@']
    cmd += ['@INPUT@']
    
    return cmd
