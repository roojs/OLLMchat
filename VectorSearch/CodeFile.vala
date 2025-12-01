namespace VectorSearch
{
	public class CodeFile : Object, Json.Serializable
	{
		public string file_path { get; set; default = ""; }
		public string language { get; set; default = ""; }
		public string raw_code { get; set; default = ""; }
		public string summary { get; set; default = ""; }
		public Gee.ArrayList<CodeElement> elements { get; set; default = new Gee.ArrayList<CodeElement>(); }
		
		public CodeFile()
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
			if (property_name == "elements") {
				this.elements.clear();
				var json_array = property_node.get_array();
				for (uint i = 0; i < json_array.get_length(); i++) {
					var element_node = json_array.get_element(i);
					this.elements.add(
						Json.gobject_deserialize(typeof(CodeElement), element_node) as CodeElement
					);
				}
				value = Value(typeof(Gee.ArrayList));
				value.set_object(this.elements);
				return true;
			}
			return default_deserialize_property(property_name, out value, pspec, property_node);
		}
	}
}

