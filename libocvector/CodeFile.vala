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
	 * Represents an import statement with module and line number.
	 */
	public class Import : Object, Json.Serializable
	{
		public string module { get; set; default = ""; }
		public int line { get; set; default = 0; }
		
		public Import()
		{
		}
	}
	
	/**
	 * Represents a code file with its analyzed elements.
	 * 
	 * This class contains data deserialized from the LLM's JSON response (summary,
	 * imports, elements) and is augmented with additional data we already have:
	 * - `language`: Programming language identifier (from file, not from LLM)
	 * - `lines`: The file contents split into lines (for code snippet extraction)
	 * - `file`: Reference to the original OLLMfiles.File object (for file path, ID, etc.)
	 * 
	 * The LLM provides structured analysis of code elements, while we provide the actual
	 * file content and metadata.
	 */
	public class CodeFile : Object, Json.Serializable
	{
		/**
		 * Programming language identifier (set from file object, not from LLM response).
		 */
		public string language { get; set; default = ""; }
		
		/**
		 * File contents split into lines (augmented by us, not from LLM).
		 * Used for efficient code snippet extraction by slicing this array.
		 */
		public string[] lines { get; set; default = {}; }
		
		/**
		 * One-paragraph summary of the file's purpose (from LLM response).
		 */
		public string summary { get; set; default = ""; }
		
		/**
		 * Import/using/include statements (from LLM response).
		 */
		public Gee.ArrayList<Import> imports { get; set; default = new Gee.ArrayList<Import>(); }
		
		/**
		 * Code elements (classes, functions, methods, etc.) extracted by LLM.
		 */
		public Gee.ArrayList<CodeElement> elements { get; set; default = new Gee.ArrayList<CodeElement>(); }
		
		/**
		 * Reference to the original file object (augmented by us, not from LLM).
		 * Provides access to file path, ID, and other file metadata.
		 */
		public OLLMfiles.File? file { get; set; default = null; }
		
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
			switch (property_name) {
				case "imports":
					this.imports.clear();
					if (property_node.get_node_type() == Json.NodeType.ARRAY) {
						var json_array = property_node.get_array();
						for (uint i = 0; i < json_array.get_length(); i++) {
							var element_node = json_array.get_element(i);
							var imp = Json.gobject_deserialize(typeof(Import), element_node) as Import;
							if (imp != null) {
								this.imports.add(imp);
							}
						}
					}
					value = Value(typeof(Gee.ArrayList));
					value.set_object(this.imports);
					return true;
				
				case "elements":
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
				
				default:
					return default_deserialize_property(property_name, out value, pspec, property_node);
			}
		}
	}
}
