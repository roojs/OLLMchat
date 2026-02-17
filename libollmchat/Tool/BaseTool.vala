/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMchat.Tool
{
	/**
	 * Abstract base class for tools that can be used with Ollama function calling.
	 *
	 * This class contains all the implementation logic. Subclasses must implement
	 * the abstract properties (name, description, parameter_description). The Function
	 * class is built from Tool's properties on construction. Parameter descriptions
	 * use a special syntax with @type, @property, and @param directives.
	 *
	 * Tools require an Agent.Interface instance to access chat, permission_provider,
	 * and add_message(). For agentic usage (with session), use Agent.Base.
	 *
	 * == Example ==
	 *
	 * {{{
	 * public class MyTool : Tool.BaseTool {
	 *     public override string name { get { return "my_tool"; } }
	 *     public override string description { get { return "Does something useful"; } }
	 *     public override string parameter_description {
	 *         get {
	 *             return """
	 * @param file_path string The path to the file
	 * @param line_number int Optional line number (default: 0)
	 * """;
	 *         }
	 *     }
	 *
	 *     public MyTool(Client? client = null) {
	 *         base(client);
	 *     }
	 *
	 *     public override async string? execute(Json.Object parameters) {
	 *         var file_path = parameters.get_string_member("file_path");
	 *         // ... tool implementation
	 *         return "Result";
	 *     }
	 * }
	 * }}}
	 *
	 * == Non-Agentic Usage ==
	 *
	 * For non-agentic usage (without session), you can create a simple dummy agent
	 * that implements Agent.Interface:
	 *
	 * {{{
	 * public class DummyAgent : Object, Agent.Interface
	 * {
	 *     private Call.Chat chat_call;
	 *     private ChatPermission.Provider my_permission_provider;
	 *     private Settings.Config2 my_config;
	 *     
	 *     public Call.Chat chat()
	 *     {
	 *         return this.chat_call;
	 *     }
	 *     
	 *     public ChatPermission.Provider get_permission_provider()
	 *     {
	 *         return this.my_permission_provider;
	 *     }
	 *     
	 *     public Settings.Config2 config()
	 *     {
	 *         return this.my_config;
	 *     }
	 *     
	 *     public DummyAgent(Call.Chat chat_call, ChatPermission.Provider permission_provider, Settings.Config2 config)
	 *     {
	 *         this.chat_call = chat_call;
	 *         this.my_permission_provider = permission_provider;
	 *         this.my_config = config;
	 *     }
	 *     
	 *     public void add_message(Message message)
	 *     {
	 *         // For non-agentic usage, add message to chat.messages
	 *         this.chat_call.messages.add(message);
	 *         // Also emit tool_message signal for UI updates if needed
	 *     }
	 * }
	 * }}}
	 *
	 * Then create the dummy agent and set it on the request:
	 *
	 * {{{
	 * var permission_provider = new ChatPermission.Dummy(); // or your custom provider
	 * var config = new Settings.Config2(); // or load from file
	 * var dummy_agent = new DummyAgent(chat_call, permission_provider, config);
	 * request.agent = dummy_agent;
	 * }}}
	 */
	public abstract class BaseTool : Object, Json.Serializable
	{
		public string tool_type { get; set; default = "function"; }
		
	// Abstract properties that subclasses must implement
		public abstract string name { get; }
		public abstract string description { get; }
		public abstract string title { get; }
		public abstract string example_call { get; }
		public abstract string  parameter_description { get; default = ""; }
		
		// Abstract method that subclasses must implement
		public abstract Type config_class();
		
		// Function instance built from Tool's properties
		public Function? function { get; set; default = null; }
		
		public bool active { get; set; default = true; }
		
		/**
		 * Whether this tool is a wrapped tool.
		 * 
		 * When true, indicates that this tool is a wrapped instance created
		 * from a .tool definition file and should use wrapped tool execution flow.
		 */
		public bool is_wrapped { get; set; default = false; }
		
		/**
		 * Command template for wrapped tools.
		 * 
		 * Contains a command template with {arguments} placeholder that will
		 * be replaced with the arguments array when executing wrapped tools.
		 * Only used when is_wrapped is true.
		 */
		public string command_template { get; set; default = ""; }

		protected BaseTool()
		{
			// Call init() to ensure proper initialization
			this.init();
		}
		
		/**
		 * Initialization method that ensures tools are properly initialized.
		 * 
		 * This method is called:
		 * - In the constructor (for normal instantiation)
		 * - After Object.new() calls (for config registration, where dummy instances are created)
		 * 
		 * Ensures tools created via Object.new() for config registration are properly initialized.
		 */
		public void init()
		{
			if (this.function != null) {
				return; // Already initialized
			}
			
			this.function = new Function() {
				name = this.name,
				description = this.description,
				parameter_description = this.parameter_description
			};
			
			// Use ParamParser to parse the parameter description
			// ParamParser.parse() can handle just parameter descriptions (it will treat it as annotations)
			var parser = new ParamParser();
			parser.parse(this.parameter_description);
			
			// Copy parsed parameters to function.parameters
			this.function.parameters = parser.parameters;
		}

		public unowned ParamSpec? find_property(string name)
		{
			return this.get_class().find_property(name);
		}

		public new void Json.Serializable.set_property(ParamSpec pspec, Value value)
		{
			base.set_property(pspec.get_name(), value);
		}

		public new Value Json.Serializable.get_property(ParamSpec pspec)
		{
			Value val = Value(pspec.value_type);
			base.get_property(pspec.get_name(), ref val);
			return val;
		}

		public Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "tool-type":
					// Exclude tool-type from serialization - it will be added manually as "type" in Chat
					return null;
				
				case "function":
					return Json.gobject_serialize(this.function);
					
				case "active":
					// Exclude these properties from serialization
					return null;
					// exculd nem etc..
				default:
					return null;
			}
		}
		
		/**
		 * Abstract method for tools to deserialize parameters into a Request object.
		 *
		 * Each tool implementation creates its specific Request type from the parameters JSON node.
		 *
		 * @param parameters_node The parameters as a Json.Node (converted from Json.Object by execute())
		 * @return A RequestBase instance or null if deserialization fails
		 */
		protected abstract RequestBase? deserialize(Json.Node parameters_node);
		
		/**
		 * Public method that creates a Request and delegates execution to it.
		 *
		 * Converts parameters to Json.Node, calls deserialize() to create a Request object,
		 * then sets tool and agent properties, and calls its execute() method.
		 *
		 * For wrapped tools, uses deserialize_wrapped() instead of deserialize().
		 *
		 * @param chat_call The chat call context for this tool execution
		 * @param tool_call The tool call object containing id, function name, and arguments
		 * @return String result or error message (prefixed with "ERROR: " for errors)
		 */
		public virtual async string execute(Call.Chat chat_call, Response.ToolCall tool_call)
		{
			// Convert parameters Json.Object to Json.Node for deserialization
			var parameters_node = new Json.Node(Json.NodeType.OBJECT);
			parameters_node.set_object(tool_call.function.arguments);
			
			// Check if this is a wrapped tool
			RequestBase? request = null;
			if (this.is_wrapped && this is WrapInterface) {
				// Wrapped tool execution flow
				var wrapped_tool = this as WrapInterface;
				request = wrapped_tool.deserialize_wrapped(parameters_node, this.command_template);
				if (request == null) {
					return "ERROR: Failed to create wrapped tool request object";
				}
				// Mark request as wrapped for tracking
				request.is_wrapped = true;
			} else {
				// Normal tool execution flow
				request = this.deserialize(parameters_node);
				if (request == null) {
					return "ERROR: Failed to create request object";
				}
			}
			
			// Set tool and agent (not in JSON, set after deserialization)
			request.tool = this;
			// Set agent property (from chat_call, set after deserialization)
			request.agent = chat_call.agent;
			
			// request_id is auto-generated via default value in RequestBase
			// Register for monitoring (works for both Agent.Base and dummy agents)
			// Interface methods have default no-op implementations
			request.agent.register_tool_monitoring(request.request_id, request);
			
			return yield request.execute();
		}
		
		/**
		 * Sets up tool configuration with default values.
		 *
		 * Default implementation for simple tools using BaseToolConfig.
		 * Creates a BaseToolConfig instance if it doesn't exist in the config.
		 * 
		 * Simple tools using BaseToolConfig don't need to override this - it's handled automatically.
		 * Complex tools that need custom config setup should override this method.
		 *
		 * @param config The Config2 instance
		 */
		public virtual void setup_tool_config_default(Settings.Config2 config)
		{
			// If config already exists, nothing to do
			if (config.tools.has_key(this.name)) {
				return;
			}
			
			// Create config instance using config_class() - works for all tool config types
			config.tools.set(this.name, Object.new(this.config_class()) as Settings.BaseToolConfig);
		}
		
		/**
		 * Registers a single tool config type with Config2.
		 *
		 * Creates a tool instance (without dependencies), gets its config class type,
		 * and registers it with Config2. Must be called before config.load_config().
		 *
		 * @param tool_type The GType of the tool class to register
		 */
		public static void register_config(Type tool_type)
		{
			// Create tool instance without parameters - works because constructors are nullable
			// Constructors handle null values gracefully (for Phase 1, we only need config_class())
			var tool = Object.new(tool_type) as Tool.BaseTool;
			
			// Register config type with Config2
			// We only need name and config_class(), which don't require init()
			var config_type = tool.config_class();
			GLib.debug("register_config: registering tool '%s' with config type %s", tool.name, config_type.name());
			Settings.Config2.register_tool_type(tool.name, config_type);
		}
		
	}
}
