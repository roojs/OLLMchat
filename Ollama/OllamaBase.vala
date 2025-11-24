namespace OLLMchat.Ollama
{
	public errordomain OllamaError {
		INVALID_ARGUMENT,
		FAILED
	}

	/**
	 * Base class for Ollama API objects that need JSON serialization.
	 * 
	 * Provides common functionality for serializing and deserializing objects
	 * to/from JSON. Used as a base for API calls and responses.
	 */
	public class OllamaBase : Object, Json.Serializable
	{
		public Client? client { get; protected set; }
		public string chat_content { get; set; default = ""; }

		protected OllamaBase(Client? client = null)
		{
			this.client = client;
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

		public virtual Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			// Block client from serialization - it's an internal reference, not API data
			if (property_name == "client") {
				return null;
			}
			return default_serialize_property(property_name, value, pspec);
		}

		public virtual bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			return default_deserialize_property(property_name, out value, pspec, property_node);
		}
	}
}

