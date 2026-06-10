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
	 * Ollama library model record (search row or per-slug JSON on disk).
	 *
	 * {@link refined} is false after a search-page parse; true after tags HTML.
	 * Persist with {@link save}; load with {@link load}.
	 */
	public class Model : Object, Json.Serializable
	{
		public string slug { get; set; default = ""; }
		public string name { get; set; default = ""; }
		public string description { get; set; default = ""; }
		public int64 pulls { get; set; default = 0; }
		public int64 downloads { get; set; default = 0; }
		public bool refined { get; set; default = false; }
		public Gee.ArrayList<string> features { get; set; default = new Gee.ArrayList<string>(); }
		public Gee.ArrayList<ModelVariant> tags { get; set; default = new Gee.ArrayList<ModelVariant>(); }

		public Gee.ArrayList<string> unique_sizes {
			get;
			private set;
			default = new Gee.ArrayList<string>();
		}

		public string display {
			owned get {
				var label = this.name != "" ? this.name : this.slug;
				if (this.description != "") {
					return label + " - " + this.description;
				}
				return label;
			}
		}

		public string list_markup {
			owned get {
				var label = this.name != "" ? this.name : this.slug;
				var s = GLib.Markup.escape_text(label, -1);
				if (this.description != "") {
					s += "\n<span size=\"small\" foreground=\"grey\">%s</span>".printf(
						GLib.Markup.escape_text(this.description, -1)
					);
				}
				var pull_count = this.downloads > 0 ? this.downloads : this.pulls;
				if (this.unique_sizes.size == 0 && this.features.size == 0 && pull_count == 0) {
					return s;
				}
				string[] parts = {};
				foreach (var size in this.unique_sizes) {
					parts += "<span background=\"#ffffcc\" size=\"small\"> %s </span>".printf(
						GLib.Markup.escape_text(size, -1)
					);
				}
				var badge_fmt = "<span background=\"%s\" foreground=\"#000000\" size=\"small\"><span font=\"Noto Color Emoji\" weight=\"normal\">%s</span> <span weight=\"bold\">%s</span></span>";
				foreach (var feature in this.features) {
					switch (feature) {
						case "embedding":
							parts += badge_fmt.printf("#e1bee7", "🏭", "embedding");
							break;
						case "tools":
							parts += badge_fmt.printf("#ffdd99", "🔧", "tools");
							break;
						case "vision":
							parts += badge_fmt.printf("#c8e6c9", "👁️", "vision");
							break;
						case "thinking":
							parts += badge_fmt.printf("#fff9c4", "🧠", "thinking");
							break;
						case "cloud":
							parts += badge_fmt.printf("#e3f2fd", "☁️", "cloud");
							break;
						default:
							parts += "<span background=\"#ccffff\" size=\"small\"> %s </span>".printf(
								GLib.Markup.escape_text(feature, -1)
							);
							break;
					}
				}
				if (pull_count > 0) {
					parts += "<span size=\"small\" foreground=\"grey\">%s</span>".printf(
						GLib.Markup.escape_text(
							pull_count >= 1000000
								? "%.1fM pulls".printf((double)pull_count / 1000000.0)
								: pull_count >= 1000
								? "%.1fk pulls".printf((double)pull_count / 1000.0)
								: "%s pulls".printf(pull_count.to_string()),
							-1
						)
					);
				}
				return s + "\n" + string.joinv(" ", parts);
			}
		}

		public void rebuild_unique_sizes()
		{
			this.unique_sizes.clear();
			var tenths_gb = new Gee.TreeSet<int>((a, b) => {
				if (a < b) {
					return -1;
				}
				if (a > b) {
					return 1;
				}
				return 0;
			});
			foreach (var variant in this.tags) {
				var gb = variant.parse_size_gb();
				if (gb < 0) {
					continue;
				}
				if (gb < 1.0) {
					tenths_gb.add((int) (gb * 10 + 0.5));
				} else {
					tenths_gb.add((int) (gb + 0.5) * 1000);
				}
			}
			foreach (var key in tenths_gb) {
				if (key >= 1000) {
					this.unique_sizes.add("%d GB".printf(key / 1000));
				} else {
					this.unique_sizes.add("%.1f GB".printf(key / 10.0));
				}
			}
		}

		public static string path(string dir, string slug)
		{
			var safe = slug.replace("/", "__");
			return GLib.Path.build_filename(dir, safe + ".json");
		}

		public static bool exists(string dir, string slug)
		{
			return GLib.FileUtils.test(
				Model.path(dir, slug),
				GLib.FileTest.EXISTS
			);
		}

		public static bool is_refined(string dir, string slug) throws GLib.Error
		{
			if (!Model.exists(dir, slug)) {
				return false;
			}
			var m = Model.load(dir, slug);
			return m.refined && m.tags.size > 0;
		}

		public static Model load(string dir, string slug) throws GLib.Error
		{
			var parser = new Json.Parser();
			parser.load_from_file(Model.path(dir, slug));
			return Json.gobject_deserialize(
				typeof(Model),
				parser.get_root()
			) as Model;
		}

		public void save(string dir) throws GLib.Error
		{
			var path = Model.path(dir, this.slug);
			var parent = GLib.Path.get_dirname(path);
			if (!GLib.FileUtils.test(parent, GLib.FileTest.IS_DIR)) {
				GLib.DirUtils.create_with_parents(parent, 0755);
			}
			GLib.FileUtils.set_contents(path, Json.gobject_to_data(this, null));
		}

		public static string json_array(Gee.ArrayList<Model> models)
		{
			var array = new Json.Array();
			foreach (var model in models) {
				array.add_element(Json.gobject_serialize(model));
			}
			var root = new Json.Node(Json.NodeType.ARRAY);
			root.init_array(array);
			return Json.to_string(root, false);
		}

		public override Json.Node serialize_property(
			string property_name,
			Value value,
			ParamSpec pspec
		)
		{
			switch (property_name) {
				case "unique_sizes":
				case "unique-sizes":
				case "display":
				case "list_markup":
				case "list-markup":
					return null;

				case "tags":
					if (this.tags.size == 0) {
						return null;
					}
					var tags_node = new Json.Node(Json.NodeType.ARRAY);
					tags_node.init_array(new Json.Array());
					var tags_array = tags_node.get_array();
					foreach (var tag in this.tags) {
						tags_array.add_element(Json.gobject_serialize(tag));
					}
					return tags_node;

				case "features":
					if (this.features.size == 0) {
						return null;
					}
					var features_node = new Json.Node(Json.NodeType.ARRAY);
					features_node.init_array(new Json.Array());
					var features_array = features_node.get_array();
					foreach (var feature in this.features) {
						features_array.add_string_element(feature);
					}
					return features_node;

				case "pulls":
					if (this.pulls == 0) {
						return null;
					}
					break;

				case "downloads":
					if (this.downloads == 0) {
						return null;
					}
					break;

				case "refined":
					if (!this.refined) {
						return null;
					}
					break;
			}
			return default_serialize_property(property_name, value, pspec);
		}

		public override bool deserialize_property(
			string property_name,
			out Value value,
			ParamSpec pspec,
			Json.Node property_node
		)
		{
			switch (property_name) {
				case "tags":
					var array = property_node.get_array();
					for (int i = 0; i < array.get_length(); i++) {
						var element = array.get_element(i);
						var tag = Json.gobject_deserialize(typeof(ModelVariant), element) as ModelVariant;
						this.tags.add(tag);
					}
					this.rebuild_unique_sizes();
					value = Value(typeof(Gee.ArrayList));
					value.set_object(this.tags);
					return true;

				case "features":
					var features_array = property_node.get_array();
					for (int i = 0; i < features_array.get_length(); i++) {
						var element = features_array.get_element(i);
						this.features.add(element.get_string());
					}
					value = Value(typeof(Gee.ArrayList));
					value.set_object(this.features);
					return true;

				case "downloads":
					if (property_node.get_node_type() == Json.NodeType.NULL) {
						this.downloads = 0;
						value = Value(typeof(int64));
						value.set_int64(0);
						return true;
					}
					return default_deserialize_property(property_name, out value, pspec, property_node);

				default:
					return default_deserialize_property(property_name, out value, pspec, property_node);
			}
		}
	}
}
