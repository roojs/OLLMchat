namespace OLLMchat.Ollama
{
	/**
	 * Represents model information from the Ollama server.
	 * 
	 * Contains model metadata including name, size, capabilities, context length,
	 * and other details. Used in model listing and model information responses.
	 */
	public class Model : BaseResponse
	{
		public string name { get; set; default = ""; }
		public string modified_at { get; set; default = ""; }
		public int64 size { get; set; default = 0; }
		public string digest { get; set; default = ""; }
		private Gee.ArrayList<string> _capabilities = new Gee.ArrayList<string>();
		public Gee.ArrayList<string> capabilities {
			get { return this._capabilities; }
			set {
				this._capabilities = value;
				// Notify computed properties that depend on capabilities
				var pspec_thinking = this.get_class().find_property("is_thinking");
				if (pspec_thinking != null) {
					this.notify(pspec_thinking);
				}
				var pspec_can_call = this.get_class().find_property("can_call");
				if (pspec_can_call != null) {
					this.notify(pspec_can_call);
				}
			}
		}

		public int64 size_vram { get; set; default = 0; }
		public int64 total_duration { get; set; default = 0; }
		public int64 load_duration { get; set; default = 0; }
		public int prompt_eval_count { get; set; default = 0; }
		public int64 prompt_eval_duration { get; set; default = 0; }
		public int eval_count { get; set; default = 0; }
		public int64 eval_duration { get; set; default = 0; }
		public string? model { get; set; } 
		public string? expires_at { get; set; }
		public int context_length { get; set; default = 0; }

		/**
		 * Returns whether the model supports thinking output
		 */
		public bool is_thinking {
			get {
				return this.capabilities.contains("thinking");
			}
			set { }
		}

		/**
		 * Returns whether the model supports tool/function calling
		 */
		public bool can_call {
			get {
				return this.capabilities.contains("tools");
			}
			set { }
		}

		/**
		 * Returns model name with size in parentheses (e.g., "llama3.1:70b (4.1 GB)")
		 */
		public string name_with_size {
			owned get {
				if (this.size == 0) {
					return this.name;
				}
				double size_gb_val = (double)this.size / (1024.0 * 1024.0 * 1024.0);
				string size_str;
				if (size_gb_val >= 1.0) {
					size_str = "%.1f GB".printf(size_gb_val);
				} else {
					size_str = "<1GB";
				}
				return "%s (%s)".printf(this.name, size_str);
			}
		}

		public Model(Client? client = null)
		{
			base(client);
		}

		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			// Exclude computed properties from deserialization
			switch (property_name) {
				case "size_gb":
				case "is_thinking":
				case "can_call":
				case "name_with_size":
					// These are computed properties, skip deserialization
					value = Value(pspec.value_type);
					return true;
				case "capabilities":
					// Handle capabilities as string array
					var capabilities = new Gee.ArrayList<string>();
					var array = property_node.get_array();
					for (int i = 0; i < array.get_length(); i++) {
						var element = array.get_element(i);
						capabilities.add(element.get_string());
					}
					value = Value(typeof(Gee.ArrayList));
					value.set_object(capabilities);
					return true;
				default:
					// Let default handler process other properties
					return default_deserialize_property(property_name, out value, pspec, property_node);
			}
		}
		
		/**
		 * Updates this model's properties from a show API response.
		 * Only updates fields that come from the show API endpoint:
		 * - modified_at
		 * - capabilities
		 * - context_length (if present in show response)
		 * 
		 * Does NOT update fields from models() API (name, size, digest) or
		 * runtime fields from ps() API (size_vram, durations, counts).
		 * 
		 * @param source The model from show API response to copy properties from
		 */
		public void updateFrom(Model source)
		{
			// Only update fields that come from show API
			this.modified_at = source.modified_at;
			
			// Update capabilities
			this.capabilities = source.capabilities;
			
			// Update context_length if present in show response
			if (source.context_length > 0) {
				this.context_length = source.context_length;
			}
			// Trigger notify signals for computed boolean properties to update UI
			// Use Vala property names (with underscores) - Vala will convert internally
			var pspec_thinking = this.get_class().find_property("is_thinking");
			if (pspec_thinking != null && pspec_thinking.get_name() == "is_thinking") {
				this.notify(pspec_thinking);
			}
			var pspec_can_call = this.get_class().find_property("can_call");
			if (pspec_can_call != null && pspec_can_call.get_name() == "can_call") {
				this.notify(pspec_can_call);
			}
		}
		
	}

}