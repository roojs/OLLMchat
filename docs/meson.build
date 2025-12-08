# Generate Valadoc documentation (single unified documentation)
# valadoc is required - meson will fail during configuration if it's not found
valadoc = find_program('valadoc', required: true)

# Combined documentation for both base and UI libraries
valadoc_dir = meson.current_source_dir() / 'ollmchat'
valadoc_clean = custom_target('valadoc-clean',
  output: 'valadoc-clean',
  command: [find_program('rm'), '-rf', valadoc_dir],
  build_by_default: false
)

# Build valadoc input list from source file variables defined in subdirs
# Combine all source files - Meson will resolve paths correctly
valadoc_input_src = []
valadoc_input_src += ollmchat_ollama_src
valadoc_input_src += ollmchat_prompt_src
valadoc_input_src += ollmchat_tools_src
valadoc_input_src += ollmchatgtk_src
valadoc_input_src += ocmarkdown_src
valadoc_input_src += ocmarkdowngtk_src
valadoc_input_src += ocsqlite_src

valadoc_docs = custom_target('valadoc',
  input: valadoc_input_src,
  output: ['valadoc'],
  depends: [valadoc_clean],
  command: [
    valadoc,
    '--package-name=ollmchat',
    '--package-version=@0@'.format(meson.project_version()),
    '--vapidir', meson.current_source_dir() / '../vapi',
    '--vapidir', meson.current_source_dir() / '../../vapi',
    '--pkg=gee-0.8',
    '--pkg=gio-2.0',
    '--pkg=glib-2.0',
    '--pkg=gobject-2.0',
    '--pkg=json-glib-1.0',
    '--pkg=libsoup-3.0',
    '--pkg=libxml-2.0',
    '--pkg=sqlite3',
    '--pkg=gtk4',
    '--pkg=gtksourceview-5',
    '--pkg=posix',
    # Don't use --pkg=ocmarkdown or --pkg=ocmarkdowngtk here - valadoc processes source files directly,
    # so it doesn't need VAPI files. Using --pkg would cause duplicate definition errors.
    '--doclet=html',
    '--directory=' + valadoc_dir,
    '@INPUT@'
  ],
  build_by_default: true,
  install: false
)
