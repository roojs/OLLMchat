# Generate Valadoc documentation (single unified documentation)
# valadoc is required - meson will fail during configuration if it's not found
#
# IMPORTANT: When adding/removing/changing source files in any library directory,
# you MUST update the input files list below to match. This includes:
# - libocsqlite, libocfiles, liboccoder, libollmchat, liboctools, etc.
# Check the corresponding meson.build file in each library directory for the
# current list of source files.
#
valadoc = find_program('valadoc', required: true)

# Use fake version file for valadoc (internal constant, not documented)

# Combined documentation for both base and UI libraries
# Output to build directory instead of source directory to keep generated files out of repository
# Valadoc creates a subdirectory with the package name (ollmchat) inside the specified directory
# So we point it to build/valadoc and it creates build/valadoc/ollmchat/
# IMPORTANT: We build docs in a slightly odd location (build/valadoc instead of standard build location),
# so we need to manually clean the directory before building to avoid "file already exists" errors.
# This clean step should NOT be removed - meson's automatic cleaning doesn't handle this case.
valadoc_dir = meson.project_build_root() / 'valadoc'
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
# Dependencies should be listed first (e.g., libocsqlite before liboccoder).
valadoc_docs = custom_target('valadoc',
  input: files(
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
    '../libocfiles/FileHistory.vala',  # Uses FileBase
    '../libocfiles/File.vala',
    '../libocfiles/FileAlias.vala',
    '../libocfiles/Folder.vala',
    '../libocfiles/FolderFiles.vala',
    '../libocfiles/GitProviderBase.vala',
    '../libocfiles/ProjectFile.vala',
    '../libocfiles/ProjectFiles.vala',
    '../libocfiles/ReviewFiles.vala',  # Uses ProjectFiles
    '../libocfiles/ProjectList.vala',
    '../libocfiles/ProjectManager.vala',
    '../libocfiles/DeleteManager.vala',  # Uses ProjectManager
    '../libocfiles/ProjectMigrate.vala',
    '../libocfiles/TreeBase.vala',  # Tree-sitter base class
    '../libocfiles/Tree.vala',  # Tree-sitter AST path lookup class
    '../libocfiles/Diff/Patch.vala',
    '../libocfiles/Diff/PatchApplier.vala',
    '../libocfiles/Diff/Differ.vala',
    # libocmarkdown sources (must come before libocmarkdowngtk)
    '../libocmarkdown/Parser.vala',
    '../libocmarkdown/TableState.vala',
    '../libocmarkdown/MarkerMap.vala',
    '../libocmarkdown/FormatMap.vala',
    '../libocmarkdown/BlockMap.vala',
    '../libocmarkdown/ListMap.vala',
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
    # libollmchat sources (depends on libocsqlite)
    '../libollmchat/namespace.vala',  # Namespace documentation
    '../libollmchat/ApplicationInterface.vala',
    '../libollmchat/Settings/namespace.vala',  # Settings namespace documentation
    '../libollmchat/Settings/Config1.vala',
    '../libollmchat/Settings/Config2.vala',
    '../libollmchat/Settings/Connection.vala',
    '../libollmchat/Settings/ConnectionModels.vala',
    '../libollmchat/Settings/ModelUsage.vala',
    '../libollmchat/Settings/BaseToolConfig.vala',
    '../libollmchat/Settings/RequiresModelsInterface.vala',
    '../libollmchat/Settings/ModelTag.vala',
    '../libollmchat/Settings/AvailableModel.vala',
    '../libollmchat/Settings/AvailableModels.vala',
    '../libollmchat/OllmError.vala',  # Must come early - used by many files
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
    '../libollmchat/Call/Create.vala',
    '../libollmchat/Call/Delete.vala',
    '../libollmchat/Message.vala',
    '../libollmchat/ChatContentInterface.vala',
    '../libollmchat/Response/namespace.vala',  # Response namespace documentation
    '../libollmchat/Response/Base.vala',
    '../libollmchat/Response/CallFunction.vala',
    '../libollmchat/Response/Chat.vala',
    '../libollmchat/Response/Embed.vala',
    '../libollmchat/Response/Model.vala',
    '../libollmchat/Response/Pull.vala',
    '../libollmchat/Response/Create.vala',
    '../libollmchat/Response/ToolCall.vala',
    '../libollmchat/Tool/namespace.vala',  # Tool namespace documentation
    '../libollmchat/Tool/RequestBase.vala',
    '../libollmchat/Tool/BaseTool.vala',
    '../libollmchat/Tool/WrapInterface.vala',
    '../libollmchat/Tool/ParamParser.vala',
    '../libollmchat/Tool/Param.vala',
    '../libollmchat/Tool/ParamSimple.vala',
    '../libollmchat/Tool/ParamObject.vala',
    '../libollmchat/Tool/ParamArray.vala',
    '../libollmchat/Tool/Function.vala',
    '../libollmchat/ChatPermission/namespace.vala',  # ChatPermission namespace documentation
    '../libollmchat/ChatPermission/Provider.vala',
    '../libollmchat/ChatPermission/Dummy.vala',
    '../libollmchat/Prompt/namespace.vala',  # Prompt namespace documentation
    '../libollmchat/Agent/namespace.vala',  # Agent namespace documentation
    '../libollmchat/Agent/Factory.vala',  # Must come before History/Manager.vala (Manager uses Agent.Factory)
    '../libollmchat/Agent/Interface.vala',  # Must come before Base (Base implements Interface)
    '../libollmchat/Agent/Base.vala',  # Must come after Factory (Base references Factory)
    '../libollmchat/Agent/JustAskFactory.vala',  # Must come after Base (JustAskFactory uses Factory)
    '../libollmchat/Agent/JustAsk.vala',  # Must come after JustAskFactory (JustAsk uses Base)
    '../libollmchat/Agent/namespace.vala',  # Agent namespace documentation
    '../libollmchat/Agent/Factory.vala',  # Must come before History/Manager.vala (Manager uses Agent.Factory)
    '../libollmchat/Agent/Interface.vala',  # Must come before Base (Base implements Interface)
    '../libollmchat/Agent/Base.vala',  # Must come after Factory (Base references Factory)
    '../libollmchat/Agent/JustAskFactory.vala',  # Must come after Base (JustAskFactory uses Factory)
    '../libollmchat/Agent/JustAsk.vala',  # Must come after JustAskFactory (JustAsk uses Base)
    '../libollmchat/History/namespace.vala',  # History namespace documentation
    '../libollmchat/History/Manager.vala',
    '../libollmchat/History/SessionList.vala',  # Must come after Manager (Manager uses SessionList)
    '../libollmchat/History/SessionBase.vala',
    '../libollmchat/History/Session.vala',
    '../libollmchat/History/EmptySession.vala',
    '../libollmchat/History/SessionJson.vala',
    '../libollmchat/History/SessionPlaceholder.vala',
    '../libollmchat/History/TitleGenerator.vala',
    '../libollmchat/Call/Generate.vala',
    '../libollmchat/Response/Generate.vala',
    # liboctools sources (depends on libollmchat and libocfiles)
    '../liboctools/ReadFile/Tool.vala',
    '../liboctools/ReadFile/Request.vala',
    '../liboctools/ReadFile/Summarize.vala',  # Tree-sitter based file summarizer
    '../liboctools/EditMode/Tool.vala',
    '../liboctools/EditMode/Request.vala',
    '../liboctools/EditMode/Stream.vala',
    '../liboctools/RunCommand/Tool.vala',
    '../liboctools/RunCommand/Bubble.vala',  # Must come before Request.vala (Request uses Bubble)
    '../liboctools/RunCommand/Scan.vala',  # Post-completion overlay scanner (must come before Overlay)
    '../liboctools/RunCommand/Overlay.vala',  # Overlay filesystem management (uses Scan)
    '../liboctools/RunCommand/Request.vala',
    '../liboctools/WebFetch/Tool.vala',
    '../liboctools/WebFetch/Request.vala',
    '../liboctools/GoogleSearch/Tool.vala',
    '../liboctools/GoogleSearch/Request.vala',
    '../liboctools/GoogleSearch/Config.vala',
    '../liboctools/ToolBuilder.vala',
    '../liboctools/Child/Parser.vala',
    '../liboctools/Child/Tool.vala',
    '../liboctools/Child/Factory.vala',
    '../liboctools/Child/Agent.vala',
    '../liboctools/Child/Request.vala',
    '../liboctools/Child/Config.vala',
    '../liboctools/Registry.vala',
    # liboccoder sources (depends on libocsqlite and libocfiles)
    '../liboccoder/namespace.vala',  # Namespace documentation
    '../liboccoder/BufferProvider.vala',
    '../liboccoder/GitProvider.vala',
    '../liboccoder/GtkSourceFileBuffer.vala',  # Must come before SourceView.vala (SourceView uses GtkSourceFileBuffer)
    '../liboccoder/SearchableDropdown.vala',
    '../liboccoder/ProjectDropdown.vala',
    '../liboccoder/FileDropdown.vala',
    '../liboccoder/SourceView.vala',
    '../liboccoder/AgentFactory.vala',  # Must come after SourceView (AgentFactory uses SourceView)
    '../liboccoder/Agent.vala',  # Must come after AgentFactory (Agent uses AgentFactory)
    '../liboccoder/List/SortedList.vala',  # Must come before Approvals (Approvals uses SortedList)
    '../liboccoder/Approvals.vala',
    '../liboccoder/AgentFactory.vala',  # Must come after SourceView (AgentFactory uses SourceView)
    '../liboccoder/Agent.vala',  # Must come after AgentFactory (Agent uses AgentFactory)
    # libocvector sources (depends on libocsqlite, libollmchat, libocfiles)
    '../libocvector/namespace.vala',  # Namespace documentation
    '../libocvector/VectorMetadata.vala',
    '../libocvector/Index.vala',
    '../libocvector/Database.vala',
    '../libocvector/VectorBase.vala',  # Base class for vector operations
    '../libocvector/Indexing/namespace.vala',  # Indexing namespace documentation
    '../libocvector/Indexing/Tree.vala',
    '../libocvector/Indexing/PromptTemplate.vala',  # Must come before Analysis (Analysis uses PromptTemplate)
    '../libocvector/Indexing/Analysis.vala',
    '../libocvector/Indexing/VectorBuilder.vala',
    '../libocvector/Indexing/DocumentationTree.vala',  # Must come before DocumentationAnalysis (DocumentationAnalysis uses DocumentationTree)
    '../libocvector/Indexing/DocumentationAnalysis.vala',  # Uses DocumentationTree and PromptTemplate
    '../libocvector/Indexing/FolderAnalysis.vala',  # Folder analysis layer (2.20.4)
    '../libocvector/Indexing/ProjectAnalysis.vala',  # Project summary and dependency extraction (2.20.5)
    '../libocvector/Indexing/ImageAnalyzer.vala',
    '../libocvector/Indexing/DocumentationVectorBuilder.vala',  # Extends VectorBuilder
    '../libocvector/Indexing/Indexer.vala',
    '../libocvector/Search/namespace.vala',  # Search namespace documentation
    '../libocvector/Search/Search.vala',
    '../libocvector/Search/SearchResult.vala',
    '../libocvector/Tool/namespace.vala',  # Tool namespace documentation
    '../libocvector/Tool/CodebaseSearchToolConfig.vala',  # Must come before CodebaseSearchTool (CodebaseSearchTool uses CodebaseSearchToolConfig)
    '../libocvector/Tool/CodebaseSearchTool.vala',
    '../libocvector/Tool/RequestCodebaseSearch.vala',
    '../libocvector/Registry.vala',
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
    '../libollmchatgtk/Tools/Permission.vala',
    '../libollmchatgtk/List/ModelUsageFilter.vala',
    '../libollmchatgtk/List/ModelUsageSort.vala',
    '../libollmchatgtk/List/ModelUsageFactory.vala',
    '../libollmchatgtk/List/SortedList.vala',
    # ollmapp application sources
    # Note: version_fake.vala must come first as it defines OLLMapp.APP_VERSION (internal, not documented)
    'version_fake.vala',
    '../ollmapp/Application.vala',
    '../ollmapp/About.vala',
    '../ollmapp/Initialize.vala',  # Must come before Window (Window uses Initialize)
    '../ollmapp/Window.vala',
    '../ollmapp/WindowPane.vala',
    '../ollmapp/FileChangeBanner.vala',
    '../ollmapp/VectorScanBanner.vala',
    # ollmapp application sources (Settings UI)
    '../ollmapp/SettingsDialog/ConnectionAdd.vala',
    '../ollmapp/SettingsDialog/ConnectionRow.vala',
    '../ollmapp/SettingsDialog/SettingsPage.vala',
    '../ollmapp/SettingsDialog/CheckingConnectionDialog.vala',
    '../ollmapp/SettingsDialog/ConnectionsPage.vala',
    '../ollmapp/SettingsDialog/ModelRow.vala',
    '../ollmapp/SettingsDialog/ModelsPage.vala',
    '../ollmapp/SettingsDialog/ProjectSearchFilter.vala',
    '../ollmapp/SettingsDialog/ProjectsPage.vala',
    '../ollmapp/SettingsDialog/AddModelDialog.vala',
    '../ollmapp/SettingsDialog/PullStatus.vala',
    '../ollmapp/SettingsDialog/PullManager.vala',
    '../ollmapp/SettingsDialog/PullManagerThread.vala',
    '../ollmapp/SettingsDialog/PullManagerBanner.vala',
    '../ollmapp/SettingsDialog/SearchablePulldown.vala',
    '../ollmapp/SettingsDialog/MainDialog.vala',
    '../ollmapp/SettingsDialog/ToolsPage.vala',
    '../ollmapp/SettingsDialog/Rows/ToolRow.vala',
    '../ollmapp/SettingsDialog/Rows/Row.vala',
    '../ollmapp/SettingsDialog/Rows/Bool.vala',
    '../ollmapp/SettingsDialog/Rows/String.vala',
    '../ollmapp/SettingsDialog/Rows/Connection.vala',
    '../ollmapp/SettingsDialog/Rows/Model.vala',
    '../ollmapp/SettingsDialog/Rows/ModelUsage.vala',
    '../ollmapp/SettingsDialog/Rows/Options.vala',
    '../ollmapp/SettingsDialog/Rows/FloatRow.vala',
    '../ollmapp/SettingsDialog/Rows/IntRow.vala',
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
    '--pkg=gio-unix-2.0',  # Required for UnixInputStream in Bubble.vala
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
    # Don't use --pkg for internal libraries (ocmarkdown, ocmarkdowngtk, ocsqlite, occoder, ocvector, octools)
    # - valadoc processes source files directly, so it doesn't need VAPI files.
    # Using --pkg would cause duplicate definition errors since the VAPI contains the same definitions.
    '--doclet=html',
    '--directory=' + valadoc_dir,
    '@INPUT@'
  ],
  build_by_default: true,
  install: false
)

