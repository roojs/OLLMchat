namespace VectorSearch
{
	public class CodeElement : Object, Json.Serializable
	{
		public string type { get; set; default = ""; }
		public string name { get; set; default = ""; }
		public int start_line { get; set; default = 0; }
		public int end_line { get; set; default = 0; }
		public string description { get; set; default = ""; }
		public string code_snippet { get; set; default = ""; }
		public string[] parameters { get; set; default = new string[0]; }
		public string return_type { get; set; default = ""; }
		public string[] dependencies { get; set; default = new string[0]; }
		
		public CodeElement()
		{
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
		
		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			return default_serialize_property(property_name, value, pspec);
		}
		
		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			return default_deserialize_property(property_name, out value, pspec, property_node);
		}
	}
}

