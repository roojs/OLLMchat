project('ollmchat', 'vala', 'c',
  version: '1.0.0',
  license: 'LGPL',
  default_options: [
    'default_library=shared',
    'c_std=gnu11',
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
subdir('libollmchat')      # Depends on libocsqlite
subdir('libollmchatgtk')   # Depends on libollmchat, libocmarkdown, libocmarkdowngtk, libocsqlite
subdir('examples')          # Depends on all libraries
subdir('docs')             # Depends on all source files
