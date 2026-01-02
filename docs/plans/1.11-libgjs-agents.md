# 1.11. libgjs for Agents - Interactive Agent Creation and Modification

## Overview

Integrate libgjs (GObject Introspection for JavaScript) to allow users to create and modify agents interactively using JavaScript. This enables dynamic agent creation, modification, and testing without recompiling the application.

## Status

⏳ **TODO** - To be implemented.

## Related Plans

- **1.10** - Refactor Agents as Interface (prerequisite - agents need to be interface layer)
- **1.3.9** - Agent Configuration (UI for agent management)
- **1.7** - Agent Management System (current agent implementation)

## Purpose

Enable users to:
- Create new agents using JavaScript
- Modify existing agent behavior with JavaScript
- Test agent changes interactively
- Share agent definitions as JavaScript files
- Build agent libraries and plugins

## libgjs Integration

### What is libgjs?

libgjs provides GObject Introspection bindings for JavaScript, allowing JavaScript code to:
- Access Vala/GObject APIs
- Create and manipulate GObject instances
- Call methods on Vala classes
- Handle signals and properties
- Use GTK widgets from JavaScript

### Architecture

**JavaScript Agent Wrapper:**
- JavaScript code defines agent behavior
- JavaScript agent extends or wraps BaseAgent
- JavaScript has access to Client, Tools, and UI APIs
- JavaScript can provide UI widgets
- JavaScript can handle tool calls

**Agent Runtime:**
- libgjs context for each agent
- Load JavaScript agent definitions
- Bridge between JavaScript and Vala
- Handle errors and exceptions
- Manage JavaScript agent lifecycle

## Implementation Details

### Phase 1: libgjs Integration

**1. Add libgjs Dependency**
- Add `gjs-1.0` to meson.build
- Add `gjs-1.0` to vapi files or use GIR
- Ensure libgjs is available at runtime

**2. Create JavaScript Agent Base**
- `libollmchat/Agent/JSAgent.vala` - Base class for JavaScript agents
- Loads JavaScript agent definitions
- Provides Vala API access to JavaScript
- Handles JavaScript errors

**3. JavaScript Agent Interface**
- JavaScript agents must export specific functions
- `generate_system_prompt(user_input)` - Generate system prompt
- `generate_user_prompt(user_input)` - Generate user prompt
- `get_widget()` - Return UI widget (optional)
- `configure_tools(tools)` - Configure tools (optional)

### Phase 2: JavaScript Agent Runtime

**1. JSAgent Class**
```vala
public class JSAgent : BaseAgent {
    private Gjs.Context context;
    private string script_path;
    
    public JSAgent(string script_path, Client client) {
        base();
        this.script_path = script_path;
        this.client = client;
        this.context = new Gjs.Context();
        load_script();
    }
    
    private void load_script() {
        // Load JavaScript file
        // Set up GObject Introspection
        // Expose Vala APIs to JavaScript
        // Call agent initialization
    }
    
    public override string generate_system_prompt(string user_input) {
        // Call JavaScript function
        return context.call_function("generate_system_prompt", user_input);
    }
}
```

**2. JavaScript API Exposure**
- Expose Client API to JavaScript
- Expose Tools API to JavaScript
- Expose UI widget creation APIs
- Expose configuration APIs

**3. Error Handling**
- Catch JavaScript errors
- Display errors to user
- Allow error recovery
- Log JavaScript errors

### Phase 3: Agent Definition Format

**JavaScript Agent Template:**
```javascript
// Agent definition file
const { BaseAgent, Client, Tools } = imports.ollmchat;

class MyCustomAgent extends BaseAgent {
    constructor(client) {
        super();
        this.client = client;
        this.name = "my-custom-agent";
        this.title = "My Custom Agent";
    }
    
    generate_system_prompt(user_input) {
        return `You are a helpful assistant. User said: ${user_input}`;
    }
    
    generate_user_prompt(user_input) {
        return user_input;
    }
    
    get_widget() {
        // Return GTK widget if needed
        return null;
    }
    
    configure_tools(tools) {
        // Configure tools for this agent
        return tools;
    }
}

// Export agent class
return MyCustomAgent;
```

### Phase 4: UI Integration

**1. Agent Editor**
- JavaScript editor in Settings dialog
- Syntax highlighting for JavaScript
- Live preview of agent behavior
- Test agent functionality

**2. Agent Library**
- Browse available JavaScript agents
- Install agents from files
- Share agents with others
- Agent marketplace (future)

**3. Agent Management**
- List JavaScript agents
- Enable/disable agents
- Edit agent JavaScript
- Delete agents

## Files to Create

### Core JavaScript Agent Support
- `libollmchat/Agent/JSAgent.vala` - JavaScript agent wrapper
- `libollmchat/Agent/JSContext.vala` - JavaScript context manager
- `libollmchat/Agent/JSApi.vala` - JavaScript API bindings

### UI Components
- `ollmchat/Settings/AgentEditor.vala` - JavaScript editor for agents
- `ollmchat/Settings/AgentLibrary.vala` - Browse and install agents

### JavaScript Templates
- `resources/agent-template.js` - Template for new agents
- `resources/agent-examples/` - Example agent definitions

## Files to Modify

- `libollmchat/Prompt/BaseAgent.vala` - Ensure compatibility with JSAgent
- `libollmchat/History/Manager.vala` - Support loading JavaScript agents
- `ollmchat/Settings/AgentsPage.vala` - Add JavaScript agent management
- `meson.build` - Add libgjs dependency
- `libollmchat/meson.build` - Add JSAgent sources

## JavaScript API Reference

### Available APIs

**Client API:**
```javascript
const client = new Client(url, api_key);
client.chat(messages, options);
client.stream(messages, options, callback);
```

**Tools API:**
```javascript
const tool = new ReadFileTool(client, project_manager);
tool.execute(params);
```

**UI Widget API:**
```javascript
const widget = new Gtk.Label({ label: "Hello" });
return widget;
```

**Configuration API:**
```javascript
const config = Config2.get_default();
config.get("key");
config.set("key", value);
```

## Security Considerations

**Sandboxing:**
- JavaScript agents run in isolated contexts
- Limit file system access
- Limit network access
- Validate JavaScript before execution

**Permissions:**
- Agent permissions system
- User approval for agent actions
- Audit agent behavior

**Validation:**
- Syntax validation
- API usage validation
- Security policy enforcement

## Use Cases

**1. Custom Prompt Agents**
- Create agents with custom system prompts
- Modify prompt behavior dynamically
- Test different prompt strategies

**2. Tool Integration Agents**
- Agents that use specific tools
- Custom tool workflows
- Agent-specific tool configurations

**3. UI-Enhanced Agents**
- Agents with custom UI widgets
- Interactive agent interfaces
- Agent-specific visualizations

**4. Agent Composition**
- Agents that use other agents
- Agent pipelines
- Agent workflows

## Future Enhancements

- **Agent Marketplace**: Share and discover agents
- **Agent Debugging**: Debug JavaScript agents
- **Agent Testing**: Unit tests for agents
- **Agent Versioning**: Version control for agents
- **Agent Dependencies**: Agent package management
- **TypeScript Support**: Type-safe agent definitions
- **Agent Hot Reload**: Reload agents without restart

## Example Agents

**Simple Prompt Agent:**
```javascript
class SimpleAgent extends BaseAgent {
    generate_system_prompt(user_input) {
        return "You are a helpful assistant.";
    }
}
```

**Code Review Agent:**
```javascript
class CodeReviewAgent extends BaseAgent {
    generate_system_prompt(user_input) {
        return `Review this code: ${user_input}. Provide feedback on code quality, best practices, and potential improvements.`;
    }
    
    configure_tools(tools) {
        // Add code reading tools
        tools.add(new ReadFileTool(this.client));
        return tools;
    }
}
```

**Interactive Agent with UI:**
```javascript
class InteractiveAgent extends BaseAgent {
    get_widget() {
        const box = new Gtk.Box({ orientation: Gtk.Orientation.VERTICAL });
        const label = new Gtk.Label({ label: "Interactive Agent" });
        box.append(label);
        return box;
    }
}
```

