/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

namespace OllamaWeb
{
	/**
	 * One pullable tag/variant for a catalog model (list + size dropdown).
	 */
	public class ModelVariant : Object, Json.Serializable
	{
		public string name { get; set; default = ""; }
		public string size { get; set; default = ""; }
		public string context { get; set; default = ""; }
		public string input { get; set; default = ""; }

		public ModelVariant()
		{
		}

		public double parse_size_gb()
		{
			if (this.size == "") {
				return -1;
			}

			var cleaned = this.size.strip().up();

			if (cleaned.has_suffix("GB")) {
				return double.parse(
					cleaned.substring(0, cleaned.length - 2).strip()
				);
			}
			if (cleaned.has_suffix("B")) {
				return double.parse(
					cleaned.substring(0, cleaned.length - 1).strip()
				) / 1e9;
			}

			return -1;
		}

		public string display_string {
			owned get {
				var parts = new Gee.ArrayList<string>();
				parts.add(this.name);

				if (this.size != "") {
					parts.add(this.size);
				}
				if (this.context != "") {
					parts.add(this.context);
				}

				return string.joinv(" • ", parts.to_array());
			}
		}

		public string dropdown_display {
			owned get {
				if (this.size != "" && this.context != "") {
					return this.name + " (" + this.size + " - context " + this.context + ")";
				}
				return this.name;
			}
		}

		public string dropdown_markup {
			owned get {
				if (this.size == "" && this.context == "" && this.input == "") {
					return GLib.Markup.escape_text(this.name, -1);
				}

				var details = "";
				if (this.size != "") {
					details = this.size;
				}
				if (this.context != "") {
					if (details != "") {
						details += " • ";
					}
					details += "context " + this.context;
				}
				if (this.input != "") {
					if (details != "") {
						details += " • ";
					}
					details += this.input;
				}

				return GLib.Markup.escape_text(this.name, -1) +
					" <span size='small' foreground='grey'>" +
					GLib.Markup.escape_text(details, -1) +
					"</span>";
			}
		}

		public override Json.Node serialize_property(
			string property_name,
			Value value,
			ParamSpec pspec
		)
		{
			switch (property_name) {
				case "display_string":
				case "display-string":
				case "dropdown_display":
				case "dropdown-display":
				case "dropdown_markup":
				case "dropdown-markup":
					return null;
				default:
					return default_serialize_property(property_name, value, pspec);
			}
		}

		public override bool deserialize_property(
			string property_name,
			out Value value,
			ParamSpec pspec,
			Json.Node property_node
		)
		{
			return default_deserialize_property(property_name, out value, pspec, property_node);
		}
	}
}
