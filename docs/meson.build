# Generate Valadoc documentation (single unified documentation)
# valadoc is required - meson will fail during configuration if it's not found
#
# IMPORTANT: When adding/removing/changing source files in any library directory,
# you MUST update the input files list below to match. This includes:
# - libocagent, libocsqlite, libocfiles, liboccoder, libollmchat, liboctools, etc.
# Check the corresponding meson.build file in each library directory for the
# current list of source files.
#
valadoc = find_program('valadoc', required: true)

# Combined documentation for both base and UI libraries
valadoc_dir = meson.current_source_dir() / 'ollmchat'
valadoc_clean = custom_target('valadoc-clean',
  output: 'valadoc-clean',
  command: [
    find_program('sh'),
    '-c',
    '''if [ -d "@0@" ]; then
      # Remove the directory completely (valadoc needs to recreate it)
      rm -rf "@0@"
    fi'''.format(valadoc_dir)
  ],
  build_by_default: false
)

# IMPORTANT: We list ALL source files explicitly instead of using --pkg for internal libraries.
# This is because valadoc processes source files directly, and using --pkg with VAPI files
# causes duplicate definition errors (the VAPI contains the same definitions as the source files).
# When adding new libraries or files, add their source files to this list rather than using --pkg.
# NOTE: File order matters! Files that define types must come before files that use those types.
# Dependencies should be listed first (e.g., libocagent before libollmchat, libocsqlite before liboccoder).
valadoc_docs = custom_target('valadoc',
  input: files(
    # libocagent sources (must come first - used by libollmchat and liboccoder)
    '../libocagent/BaseAgent.vala',
    '../libocagent/JustAsk.vala',
    # libocsqlite sources (must come before libocfiles and liboccoder which use it)
    '../libocsqlite/Database.vala',
    '../libocsqlite/Query.vala',
    '../libocsqlite/Schema.vala',
    # libocfiles sources (must come before liboccoder and liboctools which use it)
    '../libocfiles/namespace.vala',  # Namespace documentation
    '../libocfiles/BufferProviderBase.vala',
    '../libocfiles/FileBuffer.vala',  # Must come before File.vala (File uses FileBuffer)
    '../libocfiles/FileChange.vala',  # Must come after FileBuffer (FileBuffer uses FileChange)
    '../libocfiles/DummyFileBuffer.vala',
    '../libocfiles/FileBase.vala',
    '../libocfiles/File.vala',
    '../libocfiles/FileAlias.vala',
    '../libocfiles/Folder.vala',
    '../libocfiles/FolderFiles.vala',
    '../libocfiles/GitProviderBase.vala',
    '../libocfiles/ProjectFile.vala',
    '../libocfiles/ProjectFiles.vala',
    '../libocfiles/ProjectList.vala',
    '../libocfiles/ProjectManager.vala',
    '../libocfiles/ProjectMigrate.vala',
    '../libocfiles/Tree.vala',  # Tree-sitter base class
    '../libocfiles/Diff/Patch.vala',
    '../libocfiles/Diff/PatchApplier.vala',
    '../libocfiles/Diff/Differ.vala',
    # libocmarkdown sources (must come before libocmarkdowngtk)
    '../libocmarkdown/Parser.vala',
    '../libocmarkdown/RenderBase.vala',
    '../libocmarkdown/PangoRender.vala',
    '../libocmarkdown/DummyRenderer.vala',
    '../libocmarkdown/HtmlParser.vala',
    '../libocmarkdown/HtmlRender.vala',
    '../libocmarkdown/Tags.vala',
    '../libocmarkdown/TagsTable.vala',
    '../libocmarkdown/Writer.vala',
    # libocmarkdowngtk sources (depends on libocmarkdown)
    '../libocmarkdowngtk/Render.vala',
    '../libocmarkdowngtk/RenderSourceView.vala',
    '../libocmarkdowngtk/State.vala',
    '../libocmarkdowngtk/TopState.vala',
    '../libocmarkdowngtk/Table.vala',
    '../libocmarkdowngtk/TableCell.vala',
    # libollmchat sources (depends on libocagent and libocsqlite)
    '../libollmchat/namespace.vala',  # Namespace documentation
    '../libollmchat/ApplicationInterface.vala',
    '../libollmchat/Settings/namespace.vala',  # Settings namespace documentation
    '../libollmchat/Settings/Config1.vala',
    '../libollmchat/Settings/Config2.vala',
    '../libollmchat/Settings/Connection.vala',
    '../libollmchat/Settings/ConnectionModels.vala',
    '../libollmchat/Settings/ModelUsage.vala',
    '../libollmchat/Settings/BaseToolConfig.vala',
    '../libollmchat/Settings/ModelTag.vala',
    '../libollmchat/Settings/AvailableModel.vala',
    '../libollmchat/Settings/AvailableModels.vala',
    '../libollmchat/Client.vala',
    '../libollmchat/Call/namespace.vala',  # Call namespace documentation
    '../libollmchat/Call/Base.vala',
    '../libollmchat/Call/Chat.vala',
    '../libollmchat/Call/Embed.vala',
    '../libollmchat/Call/Models.vala',
    '../libollmchat/Call/Options.vala',
    '../libollmchat/Call/Ps.vala',
    '../libollmchat/Call/ShowModel.vala',
    '../libollmchat/Call/Version.vala',
    '../libollmchat/Call/Pull.vala',
    '../libollmchat/Message.vala',
    '../libollmchat/ChatContentInterface.vala',
    '../libollmchat/OllamaBase.vala',
    '../libollmchat/Response/namespace.vala',  # Response namespace documentation
    '../libollmchat/Response/Base.vala',
    '../libollmchat/Response/CallFunction.vala',
    '../libollmchat/Response/Chat.vala',
    '../libollmchat/Response/Embed.vala',
    '../libollmchat/Response/Model.vala',
    '../libollmchat/Response/Pull.vala',
    '../libollmchat/Response/ToolCall.vala',
    '../libollmchat/Tool/namespace.vala',  # Tool namespace documentation
    '../libollmchat/Tool/RequestBase.vala',
    '../libollmchat/Tool/Tool.vala',
    '../libollmchat/Tool/Param.vala',
    '../libollmchat/Tool/ParamSimple.vala',
    '../libollmchat/Tool/ParamObject.vala',
    '../libollmchat/Tool/ParamArray.vala',
    '../libollmchat/Tool/Function.vala',
    '../libollmchat/ChatPermission/namespace.vala',  # ChatPermission namespace documentation
    '../libollmchat/ChatPermission/Provider.vala',
    '../libollmchat/ChatPermission/Dummy.vala',
    '../libollmchat/Prompt/namespace.vala',  # Prompt namespace documentation
    '../libollmchat/Prompt/BaseAgent.vala',  # Must come before History/Manager.vala (Manager uses Prompt.BaseAgent)
    '../libollmchat/Prompt/JustAsk.vala',
    '../libollmchat/History/namespace.vala',  # History namespace documentation
    '../libollmchat/History/Manager.vala',
    '../libollmchat/History/SessionBase.vala',
    '../libollmchat/History/Session.vala',
    '../libollmchat/History/EmptySession.vala',
    '../libollmchat/History/SessionJson.vala',
    '../libollmchat/History/SessionPlaceholder.vala',
    '../libollmchat/History/TitleGenerator.vala',
    '../libollmchat/Call/Generate.vala',
    '../libollmchat/Response/Generate.vala',
    # liboctools sources (depends on libollmchat and libocfiles)
    '../liboctools/ReadFile.vala',
    '../liboctools/RequestReadFile.vala',
    '../liboctools/ReadFileSummarize.vala',  # Tree-sitter based file summarizer
    '../liboctools/EditMode.vala',
    '../liboctools/RequestEditMode.vala',
    '../liboctools/RunCommand.vala',
    '../liboctools/RequestRunCommand.vala',
    '../liboctools/WebFetchTool.vala',
    '../liboctools/RequestWebFetch.vala',
    '../liboctools/GoogleSearchTool.vala',
    '../liboctools/GoogleSearchRequest.vala',
    '../liboctools/GoogleSearchConfig.vala',
    '../liboctools/GoogleSearchToolConfig.vala',
    # liboccoder sources (depends on libocagent, libocsqlite, and libocfiles)
    '../liboccoder/namespace.vala',  # Namespace documentation
    '../liboccoder/BufferProvider.vala',
    '../liboccoder/GitProvider.vala',
    '../liboccoder/GtkSourceFileBuffer.vala',  # Must come before SourceView.vala (SourceView uses GtkSourceFileBuffer)
    '../liboccoder/SearchableDropdown.vala',
    '../liboccoder/ProjectDropdown.vala',
    '../liboccoder/FileDropdown.vala',
    '../liboccoder/SourceView.vala',
    '../liboccoder/Prompt/CodeAssistant.vala',
    '../liboccoder/Prompt/CodeAssistantProvider.vala',
    # libocvector sources (depends on libocsqlite, libollmchat, libocfiles)
    '../libocvector/namespace.vala',  # Namespace documentation
    '../libocvector/VectorMetadata.vala',
    '../libocvector/Index.vala',
    '../libocvector/Database.vala',
    '../libocvector/Indexing/namespace.vala',  # Indexing namespace documentation
    '../libocvector/Indexing/Tree.vala',
    '../libocvector/Indexing/Analysis.vala',
    '../libocvector/Indexing/VectorBuilder.vala',
    '../libocvector/Indexing/Indexer.vala',
    '../libocvector/Search/namespace.vala',  # Search namespace documentation
    '../libocvector/Search/Search.vala',
    '../libocvector/Search/SearchResult.vala',
    '../libocvector/Tool/namespace.vala',  # Tool namespace documentation
    '../libocvector/Tool/CodebaseSearchToolConfig.vala',  # Must come before CodebaseSearchTool (CodebaseSearchTool uses CodebaseSearchToolConfig)
    '../libocvector/Tool/CodebaseSearchTool.vala',
    '../libocvector/Tool/RequestCodebaseSearch.vala',
    '../libocvector/BackgroundScan.vala',
    # examples base classes (used by vector tools)
    '../examples/TestAppBase.vala',
    '../examples/VectorAppBase.vala',
    # libollmchatgtk sources (depends on libollmchat, libocmarkdown, libocmarkdowngtk)
    '../libollmchatgtk/ChatWidget.vala',
    '../libollmchatgtk/ChatView.vala',
    '../libollmchatgtk/ChatInput.vala',
    '../libollmchatgtk/ChatPermission.vala',
    '../libollmchatgtk/HistoryBrowser.vala',
    '../libollmchatgtk/Message.vala',
    '../libollmchatgtk/Tools/Permission.vala',
    # ollmchat application sources
    '../ollmchat/Application.vala',
    '../ollmchat/Window.vala',
    '../ollmchat/WindowPane.vala',
    '../ollmchat/FileChangeBanner.vala',
    '../ollmchat/VectorScanBanner.vala',
    # ollmchat application sources (Settings UI)
    '../ollmchat/SettingsDialog/ConnectionAdd.vala',
    '../ollmchat/SettingsDialog/ConnectionRow.vala',
    '../ollmchat/SettingsDialog/SettingsPage.vala',
    '../ollmchat/SettingsDialog/CheckingConnectionDialog.vala',
    '../ollmchat/SettingsDialog/ConnectionsPage.vala',
    '../ollmchat/SettingsDialog/ModelRow.vala',
    '../ollmchat/SettingsDialog/ModelsPage.vala',
    '../ollmchat/SettingsDialog/AddModelDialog.vala',
    '../ollmchat/SettingsDialog/PullStatus.vala',
    '../ollmchat/SettingsDialog/PullManager.vala',
    '../ollmchat/SettingsDialog/PullManagerThread.vala',
    '../ollmchat/SettingsDialog/PullManagerBanner.vala',
    '../ollmchat/SettingsDialog/SearchablePulldown.vala',
    '../ollmchat/SettingsDialog/MainDialog.vala',
    '../ollmchat/SettingsDialog/ToolsPage.vala',
    '../ollmchat/SettingsDialog/Rows/ToolRow.vala',
    '../ollmchat/SettingsDialog/Rows/Row.vala',
    '../ollmchat/SettingsDialog/Rows/Bool.vala',
    '../ollmchat/SettingsDialog/Rows/String.vala',
    '../ollmchat/SettingsDialog/Rows/Connection.vala',
    '../ollmchat/SettingsDialog/Rows/Model.vala',
    '../ollmchat/SettingsDialog/Rows/ModelUsage.vala',
    '../ollmchat/SettingsDialog/Rows/Options.vala',
    '../ollmchat/SettingsDialog/Rows/FloatRow.vala',
    '../ollmchat/SettingsDialog/Rows/IntRow.vala',
  ),
  output: ['valadoc'],
  depends: [valadoc_clean],
  command: [
    valadoc,
    '--package-name=ollmchat',
    '--package-version=@0@'.format(meson.project_version()),
    '--vapidir', meson.current_source_dir() / '../vapi',
    '--vapidir', meson.current_source_dir() / '../../vapi',
    '--vapidir', '/usr/share/vala/vapi',
    '--pkg=gee-0.8',
    '--pkg=gio-2.0',
    '--pkg=glib-2.0',
    '--pkg=gobject-2.0',
    '--pkg=json-glib-1.0',
    '--pkg=libsoup-3.0',
    '--pkg=libxml-2.0',
    '--pkg=sqlite3',
    '--pkg=gtk4',
    '--pkg=libadwaita-1',
    '--pkg=gtksourceview-5',
    '--pkg=libgit2-glib-1.0',
    '--pkg=posix',
    '--pkg=fiass',  # FAISS via vapi (used by libocvector)
    '--pkg=tree-sitter',  # Tree-sitter via vapi (used by libocvector)
    # Don't use --pkg for internal libraries (ocmarkdown, ocmarkdowngtk, ocsqlite, ocagent, occoder, ocvector, octools)
    # - valadoc processes source files directly, so it doesn't need VAPI files.
    # Using --pkg would cause duplicate definition errors since the VAPI contains the same definitions.
    '--doclet=html',
    '--directory=' + valadoc_dir,
    '@INPUT@'
  ],
  build_by_default: true,
  install: false
)

# Touch .generated file after valadoc completes
# this is used to stop the code scanner from treating generated docs as part of the codebase
valadoc_touch_generated = custom_target('valadoc-touch-generated',
  output: 'valadoc-touch-generated',
  depends: [valadoc_docs],
  command: [
    find_program('touch'),
    valadoc_dir / '.generated'
  ],
  build_by_default: true,
  install: false
)

