/*
 * Copyright (C) 2025 Alan Knowles <alan@roojs.com>
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

namespace OLLMvector
{
	/**
	 * Represents a function/method parameter with name and type.
	 */
	public class Parameter : Object, Json.Serializable
	{
		public string name { get; set; default = ""; }
		public string argument_type { get; set; default = ""; }
		
		public Parameter()
		{
		}
	}
	
	/**
	 * Represents a class/struct property or field.
	 */
	public class ElementProperty : Object, Json.Serializable
	{
		public string name { get; set; default = ""; }
		public string value_type { get; set; default = ""; }
		public Gee.ArrayList<string> accessors { get; set; default = new Gee.ArrayList<string>(); }
		
		public ElementProperty()
		{
		}
		
		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			if (property_name == "accessors") {
				this.accessors.clear();
				if (property_node.get_node_type() == Json.NodeType.ARRAY) {
					var json_array = property_node.get_array();
					for (uint i = 0; i < json_array.get_length(); i++) {
						var element = json_array.get_element(i);
						if (element.get_node_type() == Json.NodeType.VALUE) {
							this.accessors.add(element.get_string());
						}
					}
				}
				value = Value(typeof(Gee.ArrayList));
				value.set_object(this.accessors);
				return true;
			}
			return default_deserialize_property(property_name, out value, pspec, property_node);
		}
	}
	
	/**
	 * Represents a dependency relationship to another code element.
	 */
	public class Dependency : Object, Json.Serializable
	{
		public string relationship_type { get; set; default = ""; }
		public string target { get; set; default = ""; }
		
		public Dependency()
		{
		}
	}
	
	/**
	 * Represents a code element (class, function, method, struct, interface, enum, namespace)
	 * extracted from source code analysis.
	 */
	public class CodeElement : Object, Json.Serializable
	{
		public string property_type { 
			get; 
			set; 
			default = ""; 
		}
		public string name { get; set; default = ""; }
		public string access_modifier { get; set; default = ""; }
		public int start_line { get; set; default = 0; }
		public int end_line { get; set; default = 0; }
		public string signature { get; set; default = ""; }
		public string description { get; set; default = ""; }
		public string code_snippet { get; set; default = ""; }
		public Gee.ArrayList<Parameter> parameters { get; set; default = new Gee.ArrayList<Parameter>(); }
		public string return_type { get; set; default = ""; }
		public Gee.ArrayList<ElementProperty> properties { get; set; default = new Gee.ArrayList<ElementProperty>(); }
		public Gee.ArrayList<Dependency> dependencies { get; set; default = new Gee.ArrayList<Dependency>(); }
		
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
			switch (property_name) {
				case "parameters":
					this.parameters.clear();
					if (property_node.get_node_type() == Json.NodeType.ARRAY) {
						var json_array = property_node.get_array();
						for (uint i = 0; i < json_array.get_length(); i++) {
							var element_node = json_array.get_element(i);
							var param = Json.gobject_deserialize(typeof(Parameter), element_node) as Parameter;
							if (param != null) {
								this.parameters.add(param);
							}
						}
					}
					value = Value(typeof(Gee.ArrayList));
					value.set_object(this.parameters);
					return true;
				
				case "properties":
					this.properties.clear();
					if (property_node.get_node_type() == Json.NodeType.ARRAY) {
						var json_array = property_node.get_array();
						for (uint i = 0; i < json_array.get_length(); i++) {
							var element_node = json_array.get_element(i);
							var prop = Json.gobject_deserialize(typeof(ElementProperty), element_node) as ElementProperty;
							if (prop != null) {
								this.properties.add(prop);
							}
						}
					}
					value = Value(typeof(Gee.ArrayList));
					value.set_object(this.properties);
					return true;
				
				case "dependencies":
					this.dependencies.clear();
					if (property_node.get_node_type() == Json.NodeType.ARRAY) {
						var json_array = property_node.get_array();
						for (uint i = 0; i < json_array.get_length(); i++) {
							var element_node = json_array.get_element(i);
							var dep = Json.gobject_deserialize(typeof(Dependency), element_node) as Dependency;
							if (dep != null) {
								this.dependencies.add(dep);
							}
						}
					}
					value = Value(typeof(Gee.ArrayList));
					value.set_object(this.dependencies);
					return true;
				
				default:
					return default_deserialize_property(property_name, out value, pspec, property_node);
			}
		}
		
	}
}
