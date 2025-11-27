# Needed Tools Plan

This document outlines the tools that need to be implemented for the OLLMchat project, based on the Cursor agent tools specification from https://gist.github.com/sshh12/25ad2e40529b269a88b80e7cf1c38084#file-cursor-agent-tools-py

---

## Current Status Summary

**✅ Infrastructure Complete**: All base classes, permission system, and tool execution infrastructure are fully implemented and working.

**✅ Completed**:
- Base classes (Param, Tool, Function)
- Permission system with UI integration (`ChatPermission.ChatView`)
- Tool execution and auto-reply in `ChatCall.toolsReply()`
- Async permission requests (non-blocking)
- Recursive tool calling support
- Streaming support during tool execution
- ReadFileTool implementation

**⏳ Next Steps**: Implement remaining tools (RunTerminalCommandTool, WebSearchTool, CodebaseSearchTool)

**📋 Future Enhancements (Not for Initial Implementation)**:
- WebFetchTool authentication config file loading (`~/.config/ollama/tools/web_fetch.json`)

---

## Implementation Order

This plan is organized in the order components should be created:

1. **Base Classes and Support Classes** (must be created first)
2. **Tool Implementations** (created after base classes)

---

## Part 1: Base Classes and Support Classes

### 1. Param Classes

**Status**: ✅ Already created

**Purpose**: Represent parameter definitions for tool function parameters. These classes implement `Json.Serializable` to serialize parameter definitions into JSON schema format, supporting nested structures like objects and arrays.

**Classes**:
- **`Param`** (`Ollama/Tool/Param.vala`) - Base interface with only `type` property
- **`ParamSimple`** (`Ollama/Tool/ParamSimple.vala`) - For simple parameter types (string, integer, boolean)
- **`ParamObject`** (`Ollama/Tool/ParamObject.vala`) - For object parameters with nested properties
- **`ParamArray`** (`Ollama/Tool/ParamArray.vala`) - For array parameters with item definitions

**Param Interface**:
- `type` (string) - The JSON schema type (e.g., "string", "integer", "boolean", "array", "object")

**ParamSimple Properties**:
- `name` (string) - The name of the parameter
- `type` (string) - The JSON schema type (e.g., "string", "integer", "boolean")
- `description` (string) - A description of what the parameter does
- `required` (bool) - Whether this parameter is required

**ParamObject Properties**:
- `name` (string) - The name of the parameter
- `type` (string) - Always "object"
- `description` (string) - A description of what the parameter does
- `required` (bool) - Whether this parameter is required
- `properties` (`Gee.ArrayList<Param>`) - Nested properties of the object (can contain ParamObject or ParamArray instances)
- Automatically builds `required` array from properties with `required=true`

**ParamArray Properties**:
- `name` (string) - The name of the parameter
- `type` (string) - Always "array"
- `description` (string) - A description of what the parameter does
- `required` (bool) - Whether this parameter is required
- `items` (`Param`) - The item definition for array elements (can be ParamSimple, ParamObject, or ParamArray)

**Implementation**: See `src/OLLMchat/Ollama/Tool/Param.vala`, `ParamSimple.vala`, `ParamObject.vala`, and `ParamArray.vala`

---

### 2. PermissionProvider Abstract Class

**Status**: ✅ Completed (`ChatPermission/Provider.vala`)

**Purpose**: Abstract base class for requesting permission to execute tool operations. Ensures users have control over what actions are performed by the AI agent. Implemented as an abstract class (rather than interface) to allow shared functionality and properties. Includes permission storage system with JSON-based persistence.

**Location**: `src/OLLMchat/ChatPermission/Provider.vala`

**Note**: Reorganized from `Tools/PermissionProvider.vala` to top-level `ChatPermission/` folder. Base class is `Provider`, with implementations `Dummy` and `ChatView` (UI-based).
 

**Permission Storage Format** (`tool.permissions.json`):

The permissions file uses a JSON structure with full paths as keys and 3-character permission strings as values:

```json
{
    "/project/src/file.js": "rw-",
    "/usr/bin/ls": "--x", 
    "/usr/bin/rm": "---",
    "/tmp/log.txt": "???",
    "/scripts/backup.sh": "rwx"
}
```

**Permission Codes (3-character format)**:
- **r** = read allowed
- **w** = write allowed  
- **x** = execute allowed
- **-** = denied/blocked
- **?** = not asked yet (unknown)

**Permission Examples**:
- **rw-** = read + write allowed, execute denied
- **r--** = read only
- **--x** = execute only (typical for commands)
- **---** = all operations denied
- **???** = no decisions made yet

**User Response Options**:

### Allow Options
1. **allow_once** - One-time allow (stored in memory, removed after use)
2. **allow_session** - Session allow (stored in session, cleared on exit)  
3. **allow_always** - Always allow (updates r/w/x in permanent storage)

### Deny Options
4. **deny_once** - One-time deny (stored in memory, removed after use)
5. **deny_session** - Session deny (stored in session, cleared on exit)
6. **deny_always** - Always deny (updates to `-` in permanent storage)

**System Logic**:
- **Project files**: Auto-allow read, ask for writes
- **Commands**: Always ask unless in permissions
- **Unknown targets** (**???**): Ask user
- **Always allowed** (**rwx**, **r--**, etc): Auto-approve
- **Always denied** (**---**): Auto-reject

**Storage Layers**:
- **Global**: Permanent permissions (allow_always/deny_always) - stored in `tool.permissions.json`
- **Session**: Temporary permissions (allow_session/deny_session) - stored in memory for current session
- **Memory**: One-time decisions (allow_once/deny_once) - stored in memory, removed after use

**Implementation Notes**:
- All tools must be constructed with a `Client` instance, which provides access to the `permission_provider`
- Permission requests should include enough context for users to make informed decisions
- The question should describe what the tool will do with the specific parameters provided
- Tools will not execute if permission is denied
- The permission provider is shared across all tools via the `Client` instance
- The `request` method receives the `Tool` instance, allowing the permission provider to inspect the tool's properties (name, description, permission_question, permission_target_path, permission_operation) if needed
- Permissions are checked in order: Memory → Session → Global → User prompt
- Paths are normalized (absolute, symlinks resolved) for consistent storage
- Permission file is automatically created/updated in the configured directory

---

### 3. PermissionProvider Implementations

**Status**: ✅ Completed

**Dummy Implementation** (`ChatPermission/Dummy.vala`):
- Dummy implementation for testing and development
- Always denies permission (for testing)

**ChatView Implementation** (`ChatPermission/ChatView.vala`):
- UI-based implementation that shows permission widget in ChatView
- Displays question with buttons: Deny Always, Deny, Allow, Allow Once, Allow Always
- Uses async/await pattern for non-blocking permission requests
- Integrates with ChatView widget lifecycle

**Implementation**:
```vala
namespace OLLMchat.Tools
{
	/**
	 * Dummy implementation of PermissionProvider for testing.
	 * 
	 * Logs all permission requests using GLib.debug() and always denies permission.
	 */
	public class PermissionProviderDummy : PermissionProvider
	{
		public PermissionProviderDummy(string permissions_directory) : base(permissions_directory)
		{
		}
		
		protected override PermissionResponse request_user_permission(Ollama.Function tool, string question, string target_path, Operation operation)
		{
			string op_str = operation == Operation.READ ? "READ" : (operation == Operation.WRITE ? "WRITE" : "EXECUTE");
			GLib.debug("Permission requested for tool '%s' on '%s' (%s): %s", tool.name, target_path, op_str, question);
			// Always deny for dummy implementation
			return new PermissionResponse(false, PermissionStorageType.ONCE);
		}
	}
}
```

**Implementation Notes**:
- Prints permission requests using `GLib.debug()`
- Always returns `false` to deny all operations (for testing)
- Can be modified later to always return `true` for development

---

### 4. Function Base Class

**Status**: ✅ Already created (`Ollama/Tool/Function.vala`) - May need updates

**Purpose**: Abstract base class for tool functions that can be used with Ollama function calling. Implements `Json.Serializable` and provides concrete implementations of serialization methods.

**Location**: `src/OLLMchat/Ollama/Tool/Function.vala`

**Key Features**:
- Abstract base class (not an interface) that implements `Json.Serializable`
- Defines abstract properties: `name`, `description`, `param` (`Gee.ArrayList<Param>`)
- Handles permission checking via `PermissionProvider` before execution
- Provides concrete implementations of `Json.Serializable` methods with switch-case pattern in `serialize_property`
- Should parse `parameter_description` string to populate `param` array (if `parameter_description` is added)

**Parameter Documentation Format**:

Parameters will be documented using a standardized string format inspired by JSDoc/Valadoc. The `parameter_description` property (if added) contains this string, which is then parsed in the constructor to populate the `param` `Gee.ArrayList`:

```
@param parameter_name {type} [required|optional] Parameter description here
```

**Format Details**:
- `parameter_name`: The name of the parameter (used as the key in JSON schema)
- `{type}`: The parameter type (e.g., `string`, `integer`, `boolean`, `array`, `object`)
- `[required]` or `[optional]`: Indicates if the parameter is required or optional
- Description: A clear description of what the parameter does

**Examples**:
```
@param file_path {string} [required] The path to the file to read
@param start_line {integer} [optional] The starting line number to read from
@param end_line {integer} [optional] The ending line number to read to
@param read_entire_file {boolean} [optional] Whether to read the entire file
```

**Current Implementation**: See `src/OLLMchat/Ollama/Tool/Function.vala`

**Potential Updates Needed**:
- Add `parameter_description` abstract property (optional - can populate `parameters` directly instead)
- Add `parse_parameter_description()` method if using `parameter_description` string format
- Ensure `PermissionProvider` integration is complete

---

## Part 2: Tool Implementations

**Status**: ✅ Infrastructure Complete - Ready for tool implementations

The tool execution infrastructure is fully implemented:
- ✅ Tool base class (`Ollama.Tool`) with async execution
- ✅ Permission system with UI integration (`ChatPermission.ChatView`)
- ✅ Automatic tool call handling and auto-reply in `ChatCall.toolsReply()`
- ✅ Recursive tool calling support
- ✅ Streaming support during tool execution
- ✅ Error handling for tool failures

Each tool extends the `Tool` abstract class and implements:
- `name` property - The tool name (e.g., "read_file", "edit_file")
- `description` property - A detailed description of what the tool does
- `parameter_description` property - Parameter documentation string (parsed automatically)
- `prepare()` method - Builds permission question and validates parameters
- `execute_tool()` method - The actual tool implementation (synchronous, throws `Error` on failure)

### Tool Registration

Tools are registered with the Ollama client using the `addTool` method:

 

---

### Tool 1: ReadFileTool

**Status**: ✅ Completed (`Tools/ReadFileTool.vala`)

**Priority**: 1 (Essential for understanding codebase)

**Purpose**: Reads the contents of a file (and the outline). When using this tool to gather information, it's your responsibility to ensure you have the COMPLETE context.

**JSON Schema**:
```json
{
  "name": "read_file",
  "description": "Read the contents of a file (and the outline).\n\nWhen using this tool to gather information, it's your responsibility to ensure you have the COMPLETE context. Each time you call this command you should:\n1) Assess if contents viewed are sufficient to proceed with the task.\n2) Take note of lines not shown.\n3) If file contents viewed are insufficient, and you suspect they may be in lines not shown, proactively call the tool again to view those lines.\n4) When in doubt, call this tool again to gather more information. Partial file views may miss critical dependencies, imports, or functionality.\n\nIf reading a range of lines is not enough, you may choose to read the entire file.\nReading entire files is often wasteful and slow, especially for large files (i.e. more than a few hundred lines). So you should use this option sparingly.\nReading the entire file is not allowed in most cases. You are only allowed to read the entire file if it has been edited or manually attached to the conversation by the user.",
  "parameters": {
    "type": "object",
    "properties": {
      "file_path": {
        "type": "string",
        "description": "The path to the file to read."
      },
      "start_line": {
        "type": "integer",
        "description": "The starting line number to read from."
      },
      "end_line": {
        "type": "integer",
        "description": "The ending line number to read to."
      },
      "read_entire_file": {
        "type": "boolean",
        "description": "Whether to read the entire file. Only allowed if the file has been edited or manually attached to the conversation by the user."
      }
    },
    "required": ["file_path"]
  }
}
```

**Implementation Notes**:
- Should support reading specific line ranges for efficiency
- Should provide file outline/structure information
- Full file reading should be restricted to edited/attached files
- Must handle file path resolution (relative/absolute)
- Should build permission question based on parameters (file path, line range, etc.)

**Example Permission Question**:
- "Read file 'src/Example.vala' (lines 10-50)?"
- "Read entire file 'src/Example.vala'?"
- "Read file 'src/Example.vala'?"

---

### Tool 2: EditFileTool

**Status**: ✅ Completed (`Tools/EditFile.vala`, `Tools/EditFileChange.vala`)

**Note**: Implementation complete. There is a known build issue with try-finally blocks that needs to be resolved.

**Priority**: 2 (Essential for making changes)

**Purpose**: Apply a diff to a file. The diff should be a list of edits, where each edit is an object with range and replacement properties.

**JSON Schema**:
```json
{
  "name": "edit_file",
  "description": "Apply a diff to a file.\n\nThe diff should be a list of edits, where each edit is an object with the following properties:\n- 'range': The range of lines to edit, specified as [start, end].\n- 'replacement': The replacement text.\n\nThe 'range' is inclusive of the start line and exclusive of the end line. Line numbers are 1-based.\n\nIf the 'range' is [n, n], the edit is an insertion before line n.\nIf the 'range' is [n, n+1], the edit is a replacement of line n.\nIf the 'range' is [n, m] where m > n+1, the edit is a replacement of lines n through m-1.\n\nEdits should be non-overlapping and sorted in ascending order by start line.\n\nYou should always read the file before editing it to ensure you have the latest version. If you have not read the file before editing it, you may be editing an outdated version.\n\nWhen applying a diff, ensure that the diff is correct and will not cause syntax errors or other issues. If you are unsure, you can ask the user for confirmation before applying the diff.",
  "parameters": {
    "type": "object",
    "properties": {
      "file_path": {
        "type": "string",
        "description": "The path to the file to edit."
      },
      "edits": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "range": {
              "type": "array",
              "items": {
                "type": "integer"
              },
              "description": "Range of lines to edit, specified as [start, end]"
            },
            "replacement": {
              "type": "string",
              "description": "Replacement text"
            }
          },
          "required": ["range", "replacement"]
        },
        "description": "List of edits to apply"
      }
    },
    "required": ["file_path", "edits"]
  }
}
```

**Implementation Notes**:
- Line numbers are 1-based
- Range is [start, end] where start is inclusive and end is exclusive
- Edits must be non-overlapping and sorted
- Should validate edits before applying to prevent syntax errors
- Should read file first to ensure latest version
- Should build permission question showing file path and number of edits

**Example Permission Question**:
- "Edit file 'src/Example.vala' with 3 edits?"

---

### Tool 3: RunTerminalCommandTool

**Status**: ✅ Implemented (not tested) (`Tools/RunTerminalCommand.vala`, `Tools/RunTerminalCommandGtk.vala`)

**Priority**: 3 (Useful for compilation, testing, git operations)

**Purpose**: Run a terminal command in the project's root directory and return the output. Should only run commands that are safe and do not modify the user's system in unexpected ways.

**JSON Schema**:
```json
{
  "name": "run_terminal_command",
  "description": "Run a terminal command in the project's root directory and return the output.\n\nYou should only run commands that are safe and do not modify the user's system in unexpected ways.\n\nIf you are unsure about the safety of a command, ask the user for confirmation before running it.\n\nIf the command fails, you should handle the error gracefully and provide a helpful error message to the user.",
  "parameters": {
    "type": "object",
    "properties": {
      "command": {
        "type": "string",
        "description": "The terminal command to run"
      }
    },
    "required": ["command"]
  }
}
```

**Implementation Notes**:
- Commands execute in project root directory (or directory specified by permission provider)
- Validates command safety before execution
- Captures both stdout and stderr using async I/O
- Handles errors gracefully with proper error messages
- Permission caching for simple commands (based on executable realpath)
- Complex commands (with bash operators) always require approval
- GTK version (`RunTerminalCommandGtk`) provides SourceView widget for terminal output display
- Permission question shows the command to be executed

**Example Permission Question**:
- "Run command: meson compile -C build?"

---

### Tool 4: CodebaseSearchTool

**Status**: ⏳ To be created (`Tools/CodebaseSearchTool.vala`)

**Priority**: 4 (Helpful for finding relevant code - may require external semantic search service)

**⚠️ IMPLEMENTATION ORDER**: This should be the **LAST** tool to implement as it is the most complicated.

**Purpose**: Performs semantic searches within the codebase to find snippets of code most relevant to a given query. This is a semantic search tool, so the query should ask for something semantically matching what is needed.

**Semantic Search Implementation**:
- **MUST use**: [semantic-code-search](https://github.com/sturdy-dev/semantic-code-search) from sturdy-dev
- This tool provides natural language code search capabilities
- Installation: `pip3 install semantic-code-search`
- Usage: `sem --embed` to generate embeddings, then `sem 'query'` to search
- All operations are performed locally (no data leaves the user's computer)

**JSON Schema**:
```json
{
  "name": "codebase_search",
  "description": "Find snippets of code from the codebase most relevant to the search query.\nThis is a semantic search tool, so the query should ask for something semantically matching what is needed.\nAsk a complete question about what you want to understand. Ask as if talking to a colleague: 'How does X work?', 'What happens when Y?', 'Where is Z handled?'\nIf it makes sense to only search in particular directories, please specify them in the target_directories field.\nUnless there is a clear reason to use your own search query, please just reuse the user's exact query with their wording.\nTheir exact wording/phrasing can often be helpful for the semantic search query. Keeping the same exact question format can also be helpful.",
  "parameters": {
    "type": "object",
    "properties": {
      "query": {
        "type": "string",
        "description": "A complete question about what you want to understand. Ask as if talking to a colleague: 'How does X work?', 'What happens when Y?', 'Where is Z handled?'"
      },
      "target_directories": {
        "type": "array",
        "items": {
          "type": "string"
        },
        "description": "Glob patterns for directories to search over"
      },
      "explanation": {
        "type": "string",
        "description": "One sentence explanation as to why this tool is being used, and how it contributes to the goal."
      }
    },
    "required": ["query"]
  }
}
```

**Implementation Notes**:
- Semantic search requires understanding code context and meaning, not just text matching
- Should support directory filtering via glob patterns
- Query should be natural language questions about code behavior
- **MUST integrate with semantic-code-search tool** (https://github.com/sturdy-dev/semantic-code-search)
- Should build permission question showing the search query
- May need to handle embedding generation if not already done (`sem --embed`)
- Execute searches via `sem 'query'` command-line tool

**Example Permission Question**:
- "Search codebase for 'How does file reading work?'?"

---

### Tool 5: WebSearchTool

**Status**: ⏳ To be created (`Tools/WebSearchTool.vala`)

**Priority**: 5 (Useful for documentation and external information - uses API-based approach)

**Purpose**: Perform a web search using the specified query and return the top search results as markdown. Should be used when you need to find information that is not available in the codebase or when you need to verify information from external sources.

**JSON Schema**:
```json
{
  "name": "web_search",
  "description": "Perform a web search using the specified query and return the top search results as markdown.\n\nThis tool should be used when you need to find information that is not available in the codebase or when you need to verify information from external sources.\n\nBe mindful of the reliability of the sources you use, and prioritize official documentation and reputable sources.",
  "parameters": {
    "type": "object",
    "properties": {
      "query": {
        "type": "string",
        "description": "The search query"
      }
    },
    "required": ["query"]
  }
}
```

**Implementation Notes**:
- **Use Google or DuckDuckGo API** for web searches this can be set up in the constructor
    * for our test code we will add it to ollama.json
- **Return markdown version** of search results (using HTML2Markdown utility from Phase 8.5)
- Should prioritize official documentation and reputable sources
- Should return top N results (typically 10-20) converted to markdown format
- No permissions required
 
---

### Tool 6: WebFetchTool

**Status**: ⏳ To be created (`Tools/WebFetchTool.vala`)

**Priority**: 5 (Useful for fetching webpage contents)

**Purpose**: Fetch the contents of a webpage and return the content as markdown. This tool can perform GET or POST requests to retrieve webpage content.

**JSON Schema**:
```json
{
  "name": "web_fetch",
  "description": "Fetch the contents of a webpage and return the content in the specified format (markdown, raw, or base64). Multiple formats are available; base64 is recommended for binaries like images. Raw format is useful for API responses.\n\nThis tool can perform GET or POST requests to retrieve webpage content. GET requests are treated as read operations, while POST requests require write permissions. Any authentication must be configured by the client.",
  "parameters": {
    "type": "object",
    "properties": {
      "method": {
        "type": "string",
        "description": "The HTTP method to use (GET or POST only)"
      },
      "url": {
        "type": "string",
        "description": "The URL of the webpage to fetch"
      },
      "post_data": {
        "type": "string",
        "description": "The POST data to send (only required for POST requests)"
      },
      "format": {
        "type": "string",
        "enum": ["markdown", "raw", "base64"],
        "default": "markdown",
        "description": "The format to return the content in (markdown, raw, or base64). Default is markdown. Base64 is recommended for binaries like images. Raw format is useful for API responses."
      }
    },
    "required": ["method", "url"]
  }
}
```

**Implementation Notes**:
- **Only GET or POST methods** allowed
- **Return markdown version** of fetched content (using HTML2Markdown utility from Phase 8.5)
- **Authentication Configuration**:
  - Authentication must be configured by the client via a config file
  - Config file location: `.config/ollama/tools/web_fetch.json`
  - Config file format:
    ```json
    {
      "auth": {
        "sitename": {
          "headers": {
            "Authorization": "Bearer token",
            "X-API-Key": "key-value"
          }
        }
      }
    }
    ```
  - Constructor should accept path to config file and load authentication headers for matching sites
  - Match sites by hostname/domain from the URL
- **Permissions**:
  - GET requests treated as 'Read' permissions
  - POST requests follow standard file 'Write' approval flag
  - Strip query part from permission storage (e.g., `http://abc.com/test?test&test` → `http://abc.com/test`)
  - Modify permission system to recognize `http(s)://` prefix and not normalize URLs
- Should build permission question showing the URL and HTTP method
- Must handle HTTP errors gracefully

**Example Permission Question**:
- "Fetch webpage 'http://example.com/page' (GET)?"
- "Fetch webpage 'http://example.com/api' (POST)?"

---

### Tool 7: MCP Loader Tool

**Status**: ⏳ To be created (`Tools/MCPLoaderTool.vala`)

**Priority**: 6 (Advanced feature - enables external tool providers via MCP protocol)

**Purpose**: Enable MCP (Model Context Protocol) servers to provide additional tools. The tool's description lists all available MCP servers. When called, it enables all configured MCP servers and loads their tools. Uses lazy loading to reduce context size - only enabled MCP servers' tools are available. No system prompt modification needed - tool description serves as documentation.

**JSON Schema**:
```json
{
  "name": "mcp_loader",
  "description": "Enable MCP (Model Context Protocol) servers and load their tools. The description of this tool contains a list of all configured MCP servers with their names and brief descriptions. When called, this tool enables all configured MCP servers and makes their tools available. Use this tool when you need capabilities provided by MCP servers.",
  "parameters": {
    "type": "object",
    "properties": {},
    "required": []
  }
}
```

**Implementation Notes**:
- **Tool Description**: 
  - The `description` property is dynamically generated from MCP server configurations
  - Lists all configured MCP servers with their names and descriptions
  - LLM can read the tool description to discover available servers without calling it
- **Tool Execution**:
  - When called (no parameters), enables all configured MCP servers
  - Connects to each MCP server and loads its tools
  - Dynamically adds MCP server tools to `client.tools` after loading
  - Returns confirmation and list of tools now available from all enabled servers
- **Lazy Loading Strategy**: 
  - No system prompt modification needed - `mcp_loader` tool description contains server list
  - LLM reads the tool description to discover available servers
  - LLM calls `mcp_loader` when it needs MCP server capabilities
  - This reduces token usage by not including all MCP tool definitions upfront
- **MCP Protocol**: 
  - Implement MCP client protocol (JSON-RPC over stdin/stdout)
  - Standard MCP uses streaming RPC with persistent socket connection
  - Handle initialization handshake with MCP server
  - Request tool definitions via MCP protocol
  - Convert MCP tool definitions to `Tool` instances
  - **Consider stateless MCP protocol variant**: Standard MCP streaming RPC is difficult on basic HTTP servers. Consider supporting a stateless request-response version of the same protocol for HTTP REST API scenarios - this would be powerful for deployment on standard web servers while maintaining full MCP context and functionality
- **MCP Tool Wrapper**: 
  - Each MCP tool is wrapped in a `Tool` instance
  - Tool execution delegates to MCP server via JSON-RPC
  - Results are formatted and returned to Ollama
- **Server Management**:
  - MCP server configurations stored in config file (e.g., `ollama.json`)
  - Track enabled/disabled state per chat session
  - Support multiple MCP servers enabled simultaneously
  - Handle connection errors gracefully
- **No permissions required** for MCP tools (servers are configured by user)

**MCP Server Configuration Format** (example):
```json
{
  "mcp_servers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/allowed/dir"],
      "description": "Provides file system operations"
    },
    "brave-search": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-brave-search"],
      "env": {
        "BRAVE_API_KEY": "your-api-key"
      },
      "description": "Provides web search capabilities via Brave Search API"
    }
  }
}
```

---

## Implementation Considerations

### Tool Integration with Ollama

These tools are designed to be used with Ollama's function calling capabilities. Each tool should:

1. **Extend Tool**: Extend the `Tool` abstract class (not `Function`). The `Function` class is automatically created from the `Tool`'s properties.
2. **Require Client**: All tools must be constructed with a `Client` instance, which provides access to the `permission_provider`
3. **Define Abstract Properties**: Implement the abstract properties:
   - `name` (string) - The tool name (e.g., "read_file", "edit_file")
   - `description` (string) - A detailed description of what the tool does
   - `parameter_description` (string) - Parameter documentation in `@param` format (automatically parsed to build `Function.parameters`)
4. **Parameter Parsing**: The `parameter_description` string is automatically parsed in the constructor using the format:
   ```
   @param parameter_name {type} [required|optional] Parameter description here
   ```
   This populates the `Function.parameters` property (a `ParamObject` containing `ParamSimple` instances).
5. **Implement prepare()**: Build permission information by setting:
   - `permission_question` - The question to ask the user
   - `permission_target_path` - The target path/resource (e.g., file path, URL, command)
   - `permission_operation` - The operation type (READ, WRITE, or EXECUTE)
   - Return `true` if permission check is needed, `false` to skip
6. **Implement execute_tool()**: Perform the actual tool operation. Use `readParams(parameters)` to read JSON parameters into object properties. Return a string result (will be wrapped in JSON automatically).
7. **Error Handling**: Throw `Error` exceptions from `execute_tool()` - they will be caught and formatted as `"ERROR: <message>"` by the base `execute()` method.
8. **Tool Registration**: Register tools with `client.addTool(tool)` - the tool instance is added directly to `client.tools` array.

### Tool Execution Flow

1. **Tool Definition**: Create tool classes extending `Tool` abstract class, constructed with a `Client` instance (which provides `permission_provider`)
2. **Tool Registration**: Call `client.addTool(tool)` - the tool instance is added directly to `client.tools` array. The `Tool` constructor automatically creates a `Function` instance from the tool's properties.
3. **Function Calling**: When Ollama requests a tool call, find the appropriate tool by name from `client.tools` and call `execute(parameters)` (async method)
4. **Permission Check**: The `execute()` method calls `prepare(parameters)` to build permission information. If `prepare()` returns `true`, it calls `client.permission_provider.request(this)` (async) which:
   - Checks storage layers (Memory → Session → Global)
   - Prompts user if needed via UI
   - Returns `true` if permission granted, `false` if denied
5. **Permission Denial Handling**: If permission is denied:
   - Tool's `execute()` method returns `"ERROR: Permission denied: <question>"`
   - Chat flow stops immediately and returns the current response object (the assistant's response that requested the tool)
   - No error message is shown to the user - chat flow ends silently
   - The entire tool calling sequence is aborted (even if multiple tools were requested)
6. **Tool Execution**: If permission is granted (or `prepare()` returned `false`), the tool executes its `execute_tool(parameters)` method:
   - Use `readParams(parameters)` to read JSON parameters into object properties
   - Perform the actual operation
   - Return a string result (errors should throw `Error` exceptions)
7. **Result Formatting**: Tool results are automatically formatted as JSON and sent back to Ollama as a function result message. Errors are formatted as `"ERROR: <message>"`.
8. **Response Handling**: Ollama will process the tool results and continue the conversation
9. **Recursive Tool Calling**: Tool calling may happen multiple times before final response - assistant may request more tools, which are executed automatically until final response or permission denial

### Directory Structure

```
src/OLLMchat/
├── Ollama/
│   ├── Tool/
│   │   ├── Tool.vala           # Abstract base class for all tools ✅
│   │   ├── Function.vala        # Concrete class built from Tool's properties ✅
│   │   ├── Param.vala            # Base parameter interface ✅
│   │   ├── ParamSimple.vala      # Simple parameter class ✅
│   │   ├── ParamObject.vala       # Object parameter class ✅
│   │   └── ParamArray.vala        # Array parameter class ✅
│   └── Client.vala               # Client with addTool() method ✅
├── ChatPermission/
│   ├── Provider.vala                  # Permission provider abstract class ✅
│   ├── Dummy.vala                     # Dummy permission provider ✅
│   └── ChatView.vala                   # UI-based permission provider ✅
├── Tools/
│   ├── ReadFileTool.vala              # Read file tool ✅
│   ├── EditFile.vala                  # Edit file tool ✅
│   ├── EditFileChange.vala            # Edit change class ✅
│   ├── RunTerminalCommandTool.vala    # Terminal command tool ✅
│   ├── HTML2Markdown.vala            # HTML to markdown converter ⏳
│   ├── WebSearchTool.vala            # Web search tool ⏳
│   ├── WebFetchTool.vala             # Web fetch tool ⏳
│   ├── CodebaseSearchTool.vala        # Codebase search tool ⏳
│   ├── MCPLoaderTool.vala            # MCP server loader tool ⏳
│   └── MCP/
│       ├── Client.vala                # MCP protocol client ⏳
│       ├── ToolWrapper.vala          # Wrapper for MCP tools ⏳
│       └── Config.vala               # MCP server configuration ⏳
```

---

## To-Do List

### Phase 1: Param Classes

- [x] **Param** - Create `Param.vala` base interface with only `type` property
- [x] **ParamSimple** - Create `ParamSimple.vala` class for simple parameter types (string, integer, boolean)
- [x] **ParamObject** - Create `ParamObject.vala` class for object parameters with nested properties
- [x] **ParamArray** - Create `ParamArray.vala` class for array parameters with item definitions

### Phase 2: PermissionProvider

- [x] **PermissionProvider** - Create `PermissionProvider.vala` abstract class

### Phase 3: PermissionProviderDummy

- [x] **PermissionProviderDummy** - Create `PermissionProviderDummy.vala` implementation

### Phase 4: Function Updates

- [x] **Function Updates** - Review and update `Function.vala` if needed (add `parameter_description` parsing if desired)
  - [x] Updated `Tool` to be abstract base class with all implementation logic
  - [x] Updated `Function` to be concrete class built from `Tool`'s properties
  - [x] Implemented `parameter_description` parsing with state machine
  - [x] Added `parse_parameter_description_string()` method using ParseState enum
  - [x] Added constructor logic to handle multi-line parameter descriptions
  - [x] Added `prepare()` abstract method for building permission questions
  - [x] Added `execute_tool()` abstract method for tool execution
  - [x] Integrated permission checking in `execute()` method
  - [x] Added `return_error()` helper method for standardized error responses

### Phase 5: ReadFileTool

- [x] **ReadFileTool** - Create `ReadFileTool.vala` (Priority 1) ✅
  - [x] Implement file reading with line range support
  - [x] Implement file outline/structure information
  - [x] Add permission question building
  - [x] Add to meson.build
  - [x] Test with PermissionProvider

### Phase 6: Tool Call Handling and Auto-Reply

- [x] **Tool Call Handling** - Implement correct chat behavior for handling tool calls ✅
  - [x] Add `tool_calls` property (`Gee.ArrayList<Json.Node>`) to Message class for assistant messages
  - [x] Add `tool_call_id` property (string) to Message class for tool role messages
  - [x] Add `name` property (string) to Message class for tool role messages (tool function name)
  - [x] Update Message serialization to handle tool_calls (convert Gee.ArrayList to Json.Array)
  - [x] Update Message deserialization to handle tool_calls (convert Json.Array to Gee.ArrayList)
  - [x] Update ChatResponse to detect tool calls when response is done
  - [x] Implement automatic tool execution in ChatCall (async/await)
  - [x] Implement auto-reply mechanism to continue conversation after tool execution
  - [x] Ensure recursive tool calling works (multiple tool call rounds before final response)
  - [x] Ensure chat() only returns after final response (not after tool calls)
  - [x] Ensure streaming works correctly during tool execution and auto-reply
  - [x] Handle multiple tool calls in one response correctly
  - [x] Handle tool execution failures gracefully
  - [x] Implement async permission requests (non-blocking UI)

**Tool Call Flow**:
1. User sends a chat message
2. Assistant responds with `role: "assistant"` and `tool_calls` array
3. System automatically executes all tool calls
4. System adds the assistant message with `tool_calls` to the conversation (tool request)
5. System executes each tool call
6. System adds tool result messages as `role: "tool"` messages with `tool_call_id` and `name` (tool reply)
7. System automatically continues the conversation (auto-reply) with both the tool request and tool reply
8. Steps 2-7 may repeat multiple times (tool calling can happen recursively until final response)
9. Assistant provides final response (no more tool calls)
10. Only then does `chat()` return to the caller

**Key Files to Modify**:
- `src/OLLMchat/Ollama/Message.vala` - Add tool_calls, tool_call_id, name properties
- `src/OLLMchat/Ollama/Response/ChatResponse.vala` - Detect tool calls and trigger execution
- `src/OLLMchat/Ollama/Call/ChatCall.vala` - Implement tool execution and auto-reply logic
- `src/OLLMchat/Ollama/Client.vala` - Ensure chat() waits for final response

**Message Structure**:
```json
// Assistant message with tool calls:
{
  "role": "assistant",
  "content": "...",
  "tool_calls": [
    {
      "id": "call_123",
      "type": "function",
      "function": {
        "name": "read_file",
        "arguments": "{\"file_path\": \"src/Example.vala\"}"
      }
    }
  ]
}

// Tool result message:
{
  "role": "tool",
  "tool_call_id": "call_123",
  "name": "read_file",
  "content": "file contents..."
}
```

### Phase 7: EditFileTool

- [x] **EditFileTool** - Create `EditFile.vala` and `EditFileChange.vala` (Priority 2) ✅
  - [x] Implement diff application with range validation
  - [x] Implement edit validation (non-overlapping, sorted)
  - [x] Add permission question building
  - [x] Add to meson.build
  - [x] Add to TestWindow for testing
  - [ ] **Testing** - Comprehensive testing of EditFileTool functionality

### Phase 8: RunTerminalCommandTool

- [x] **RunTerminalCommandTool** - Create `RunTerminalCommandTool.vala` (Priority 3) ✅
  - [x] Implement command execution in project root
  - [x] Implement stdout/stderr capture
  - [x] Add command safety validation
  - [x] Add timeout handling
  - [x] Add permission question building
  - [x] Add to meson.build
  - [ ] **Testing** - Comprehensive testing of RunTerminalCommandTool functionality

### Phase 8.5: HTML to Markdown Converter

- [ ] **HTML2Markdown** - Port html2md from C++ to Vala
  - [ ] Port `html2md.cpp` from https://github.com/tim-gromeyer/html2md to Vala
  - [ ] Create `Tools/HTML2Markdown.vala` utility class
  - [ ] Implement HTML parsing and conversion to markdown
  - [ ] Support all HTML tags handled by original C++ implementation
  - [ ] Add to meson.build
  - [ ] Test with various HTML inputs

### Phase 9: WebSearchTool

- [ ] **WebSearchTool** - Create `WebSearchTool.vala` (Priority 5)
  - [ ] **Use Google or DuckDuckGo API** for web searches
  - [ ] **Return markdown version** of search results (using HTML2Markdown from Phase 8.5)
  - [ ] Implement API integration (Google Custom Search API or DuckDuckGo API)
  - [ ] Convert HTML search results to markdown format
  - [ ] Implement result filtering/ranking
  - [ ] **Implement rate limiting**: Max 10 searches per 15-minute sliding window
  - [ ] **Add timestamp tracking**: Maintain `ArrayList<DateTime>` of search timestamps per chat session
  - [ ] **Implement pruning logic**: Remove timestamps older than 15 minutes before each search
  - [ ] **Implement permission request**: When limit reached, ask user permission and clear list if granted
  - [ ] **Add chat ID tracking** (may need to add chat_id to ChatCall or use ChatWidget's current_chat)
  - [ ] Add permission question building (include search query in question)
  - [ ] Add to meson.build
  - [ ] Test with PermissionProviderDummy

### Phase 10: WebFetchTool

- [ ] **WebFetchTool** - Create `Tools/WebFetchTool.vala` (Priority 5)
  
  **Design Considerations**:
  - Designed to be extensible - WebSearchTool will extend this class
  - Use protected methods for HTTP fetching logic so subclasses can reuse
  - Keep core fetching logic separate from format conversion for reusability
  
  **Format Handling Rules**:
  - **Automatic format detection based on Content-Type**:
    - `image/*` → automatically converted to base64 (regardless of format parameter)
    - `text/*` → raw format (except HTML which converts to markdown if format="markdown")
    - `application/json` → raw format
    - Any non-text content type → base64 (regardless of format parameter)
  - **User-specified format parameter** only applies when content is text/HTML
  
  **Step 1: Create Base Class Structure**
  - [ ] Create `Tools/WebFetchTool.vala` extending `Ollama.Tool`
  - [ ] Define parameter properties:
    - [ ] `method` (string) - HTTP method (GET or POST)
    - [ ] `url` (string) - URL to fetch
    - [ ] `post_data` (string) - POST data (optional)
    - [ ] `format` (string) - Output format: "markdown", "raw", or "base64" (default: "markdown")
  - [ ] Implement abstract properties:
    - [ ] `name` → return `"web_fetch"`
    - [ ] `description` → return full description from JSON schema
    - [ ] `parameter_description` → return `@param` formatted documentation
  - [ ] Constructor: `WebFetchTool(Ollama.Client client)`
    - [ ] Simple constructor (no config loading in initial implementation)
  
  **Step 2: URL Processing and Permission Handling**
  - [ ] Create `normalize_url_for_permission(string url)` method
    - [ ] Strip query string from URL (everything after `?`)
    - [ ] Remap `http://` to `https://` (normalize all to HTTPS for permission storage)
    - [ ] Return normalized URL for permission storage
  - [ ] Implement `prepare(Json.Object parameters)` method
    - [ ] Read parameters using `readParams(parameters)`
    - [ ] Validate `method` is "GET" or "POST" (throw error if invalid)
    - [ ] Validate `url` is not empty
    - [ ] Validate `post_data` is provided if method is "POST"
    - [ ] Set `permission_target_path` = normalized URL (without query)
    - [ ] Set `permission_operation` = `READ` for GET, `WRITE` for POST
    - [ ] Set `permission_question` = "Fetch webpage '{url}' ({method})?"
    - [ ] Return `true` (always requires permission)
  
  **Step 4: HTTP Fetching Logic (Protected Methods for Extensibility)**
  - [ ] Create protected async method `fetch_http(string method, string url, string? post_data, Gee.HashMap<string, string>? extra_headers = null) throws Error`
    - [ ] Create `Soup.Session` instance (or reuse if available)
    - [ ] Set session timeout (e.g., 30 seconds)
    - [ ] Create `Soup.Message` with method and URL
    - [ ] Add authentication headers from config (call `get_auth_headers(url)`)
    - [ ] Add any extra headers passed as parameter
    - [ ] Set Content-Type header for POST requests (if post_data provided)
    - [ ] Set request body for POST requests using `message.set_request_body_from_bytes()`
    - [ ] Execute async request using `session.send_and_read_async()`
    - [ ] Check status code - throw error if not 2xx
    - [ ] Return `Bytes` object with response body
  - [ ] Create protected method `get_content_type(Soup.MessageHeaders headers)` 
    - [ ] Extract Content-Type header
    - [ ] Return content type string (e.g., "text/html", "application/json", "image/png")
  
  **Step 5: Format Conversion**
  - [ ] Create `convert_to_format(Bytes response_bytes, string content_type, string format)` method
    - [ ] If format is "base64":
      - [ ] Convert bytes to base64 using `GLib.Base64.encode()`
      - [ ] Return base64 string
    - [ ] If format is "raw":
      - [ ] Convert bytes to string using `response_bytes.get_data()` and UTF-8 decoding
      - [ ] Return raw string
    - [ ] If format is "markdown":
      - [ ] Convert bytes to string (UTF-8)
      - [ ] Check if content is HTML (Content-Type contains "html" or starts with "<")
      - [ ] If HTML: Use `Markdown.FromHTML` to convert to markdown
      - [ ] If not HTML: Return as-is (assume already text/markdown)
      - [ ] Return markdown string
  
  **Step 6: Tool Execution**
  - [ ] Implement `execute_tool(Json.Object parameters) throws Error`
    - [ ] Re-read parameters using `readParams(parameters)`
    - [ ] Validate parameters again
    - [ ] Call `fetch_http()` to get response bytes
    - [ ] Get content type from response headers
    - [ ] Call `convert_to_format()` to convert response
    - [ ] Send tool message: "Fetched {url} ({format})"
    - [ ] Return converted content string
  
  **Step 7: Error Handling**
  - [ ] Handle network errors (connection timeout, DNS failure, etc.)
    - [ ] Catch `GLib.IOError` and wrap with descriptive message
  - [ ] Handle HTTP errors (4xx, 5xx status codes)
    - [ ] Check status code in `fetch_http()` and throw error with status code
  - [ ] Handle invalid URLs
    - [ ] Validate URL format before making request
  - [ ] Handle JSON config parsing errors
    - [ ] Log error but continue without auth (don't fail tool creation)
  
  **Step 8: Integration**
  - [ ] Add to `meson.build` in `ollmchat_tools_src` list
  - [ ] Register tool in application (where other tools are registered)
  - [ ] Test with `PermissionProviderDummy`
  - [ ] Test GET requests with various URLs
  - [ ] Test POST requests
  - [ ] Test format conversion (markdown, raw, base64)
  - [ ] Test authentication config loading
  - [ ] Test error handling (invalid URLs, network errors, HTTP errors)
  
  **Step 9: Permission System Updates (if needed)**
  - [ ] Verify permission system handles URLs correctly
  - [ ] Ensure `http://` and `https://` prefixes are preserved (not normalized)
  - [ ] Test permission caching with normalized URLs (query stripped)
  
  **Dependencies**:
  - `libsoup-3.0` (already in base_deps)
  - `Markdown.FromHTML` (already exists in codebase)
  - `json-glib-1.0` (already in base_deps)
  
  **Files to Create**:
  - `Tools/WebFetchTool.vala`
  
  **Files to Modify**:
  - `meson.build` - Add WebFetchTool to source list
  - Application initialization - Register WebFetchTool with client

### Phase 11: CodebaseSearchTool

- [ ] **CodebaseSearchTool** - Create `CodebaseSearchTool.vala` (Priority 4)
  - [ ] ⚠️ **IMPLEMENT LAST** - This is the most complicated tool
  - [ ] Integrate with semantic-code-search (https://github.com/sturdy-dev/semantic-code-search)
  - [ ] Install semantic-code-search dependency (`pip3 install semantic-code-search`)
  - [ ] Handle embedding generation (`sem --embed`) if needed
  - [ ] Execute searches via `sem 'query'` command-line tool
  - [ ] Implement directory filtering via glob patterns
  - [ ] Add permission question building
  - [ ] Add to meson.build
  - [ ] Test with PermissionProviderDummy

### Phase 12: MCP Server Support

- [ ] **MCP Loader Tool** - Create `Tools/MCPLoaderTool.vala` and MCP server integration
  - [ ] **MCP Server Configuration**: Accept MCP server configuration (name, command, args, env, etc.) stored in config file
  - [ ] **MCP Loader Tool** (`mcp_loader`):
    - [ ] Lists all available MCP servers in its description
    - [ ] Description dynamically includes server names and brief descriptions from config
    - [ ] LLM can read the tool description to discover available MCP servers
    - [ ] When called (no parameters), enables all configured MCP servers and loads their tools
    - [ ] Connects to each MCP server and loads its tools
    - [ ] Dynamically adds MCP server tools to `client.tools` after loading
    - [ ] Returns confirmation and list of tools now available from all enabled servers
  - [ ] **MCP Protocol Implementation**:
    - [ ] Implement MCP client protocol (stdin/stdout JSON-RPC communication)
    - [ ] Handle MCP server initialization handshake
    - [ ] Request and parse tool definitions from MCP server
    - [ ] Convert MCP tool definitions to `Tool` instances
    - [ ] Handle MCP tool execution and result formatting
    - [ ] **Consider stateless MCP protocol variant**: Standard MCP uses streaming RPC (persistent socket), which is difficult on basic HTTP servers. Consider supporting a stateless request-response version of the same protocol for HTTP REST API scenarios - this would be powerful for deployment on standard web servers
  - [ ] **MCP Server Management**:
    - [ ] Store MCP server configurations (possibly in `ollama.json` or separate config file)
    - [ ] Track enabled/disabled state per chat session
    - [ ] Handle MCP server connection errors gracefully
    - [ ] Support multiple MCP servers enabled simultaneously
  - [ ] **Tool Wrapper**: Create wrapper `Tool` instances for MCP tools that delegate execution to MCP server
  - [ ] No permissions required for MCP tools (servers are configured by user)
  - [ ] Add to meson.build
  - [ ] Test with sample MCP servers

**Implementation Notes**:
- MCP (Model Context Protocol) allows external servers to provide tools/functions
- **No system prompt modification needed** - tool description serves as documentation
- LLM discovers available MCP servers by reading the `mcp_loader` tool description
- When LLM calls `mcp_loader`, it enables all configured servers and loads their tools
- Lazy loading reduces token usage by only including enabled MCP server tools
- MCP servers communicate via JSON-RPC over stdin/stdout (standard MCP uses streaming RPC with persistent socket)
- Each MCP tool should be wrapped in a `Tool` instance that executes via MCP protocol
- Consider caching MCP tool definitions after first load
- **Stateless MCP Protocol Variant**: Standard MCP uses streaming RPC (persistent socket), which is difficult to implement on basic HTTP servers. Consider supporting a stateless request-response version of the same protocol for HTTP REST API scenarios - this would be powerful for deployment on standard web servers while maintaining full MCP context and functionality

### Phase 13: Integration and Testing

- [x] **Tool Registration** - Ensure `Client.addTool()` method works correctly ✅
- [x] **Permission Integration** - Create UI-based PermissionProvider implementation (`ChatPermission.ChatView`) ✅
- [x] **End-to-End Testing** - Test tool execution flow with Ollama function calling ✅
- [x] **Error Handling** - Ensure all tools handle errors gracefully ✅
- [ ] **Documentation** - Update documentation with tool usage examples

### Phase 14: UI Integration

- [x] **PermissionProviderUI** - Create UI-based permission provider (`ChatPermission.ChatView`) ✅
  - [x] Permission widget with question and buttons
  - [x] Async permission requests (non-blocking)
  - [x] Integration with ChatView widget lifecycle
- [x] **Tool Status Display** - Show tool execution status in UI ✅
- [x] **Tool Results Display** - Display tool results in chat interface ✅

---

## References

- Cursor Agent Tools: https://gist.github.com/sshh12/25ad2e40529b269a88b80e7cf1c38084#file-cursor-agent-tools-py
- Ollama Function Calling: https://github.com/ollama/ollama/blob/main/docs/function-calling.md
