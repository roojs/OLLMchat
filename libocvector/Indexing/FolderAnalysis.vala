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

namespace OLLMvector.Indexing
{
	/**
	 * Analysis layer for folder/directory processing.
	 *
	 * Processes Folder objects and generates one-line descriptions using LLM.
	 * Analyzes folders by querying child folder descriptions and file descriptions
	 * from the database, then generates a summary of the folder's contents.
	 */
	public class FolderAnalysis : VectorBase
	{
		private SQ.Database sql_db;
		private static PromptTemplate? cached_folder_template = null;

		/**
		 * Static constructor - loads template at class initialization.
		 */
		static construct
		{
			try {
				cached_folder_template = new PromptTemplate("analysis-prompt-folder.txt");
				cached_folder_template.load();
			} catch (GLib.Error e) {
				GLib.critical("Failed to load folder prompt template in static constructor: %s", e.message);
			}
		}

		/**
		 * Constructor.
		 *
		 * @param config The Config2 instance containing tool configuration
		 * @param sql_db The SQLite database for syncing after folder processing
		 */
		public FolderAnalysis(OLLMchat.Settings.Config2 config, SQ.Database sql_db)
		{
			base(config);
			this.sql_db = sql_db;
		}

		/**
		 * Recursive entry: analyze children first, then this folder.
		 *
		 * For each direct child that is a Folder, yields to analyze_children(child, metadata_keymap).
		 * For each alias (base_type "fa") whose points_to is a Folder, yields to analyze_children(points_to, metadata_keymap).
		 * Once all children are done, calls analyze(folder, metadata_keymap) and updates
		 * metadata_keymap with the new folder VectorMetadata (store full object, do not copy description).
		 *
		 * @param folder The folder to process
		 * @param metadata_keymap Id-indexed map ((int)file_id → VectorMetadata); key type is int (cast from int64); updated when this folder is analyzed
		 * @return Number of folders analyzed in this subtree
		 */
		public async int analyze_children(OLLMfiles.Folder folder, Gee.HashMap<int, VectorMetadata> metadata_keymap) throws GLib.Error
		{
			int count = 0;

			// Recurse into child folders first (bottom-up). Include alias→folder: when points_to is a Folder, recurse into it.
			foreach (var child in folder.children.items) {
				if (child is OLLMfiles.Folder) {
					count += yield this.analyze_children((OLLMfiles.Folder)child, metadata_keymap);
					continue;
				}
				var fb = (OLLMfiles.FileBase)child;
				if (fb.base_type == "fa" && fb.points_to is OLLMfiles.Folder) {
					count += yield this.analyze_children((OLLMfiles.Folder)fb.points_to, metadata_keymap);
				}
			}

			// Then analyze this folder and update keymap with full VectorMetadata (analyze returns non-null; empty description = skip)
			var meta = yield this.analyze(folder, metadata_keymap);
			if (meta.description != "") {
				metadata_keymap.set((int)folder.id, meta);
				count++;
			}

			return count;
		}

		/**
		 * Per-folder analysis: build context from metadata_keymap, call LLM, save to DB, update keymap.
		 *
		 * Builds context from metadata_keymap: get VectorMetadata by (int)child.id/(int)file_id, use
		 * .description and .element_name from the stored object (do not copy out description only).
		 *
		 * @param folder The folder to analyze
		 * @param metadata_keymap Id-indexed map ((int)file_id → VectorMetadata); read for children/files, write for (int)folder.id when done
		 * @return VectorMetadata for this folder; on failure returns VectorMetadata with description = "" (never null)
		 */
		private async VectorMetadata analyze(OLLMfiles.Folder folder, Gee.HashMap<int, VectorMetadata> metadata_keymap) throws GLib.Error
		{
			// Build folder contents: one pass over children, each line tagged (folder), (file), or (alias) from base_type.
			// Descriptions from keymap are stored stripped when saved, so use vm.description as-is.
			string[] folder_contents_lines = {};
			foreach (var child in folder.children.items) {
				var fb = (OLLMfiles.FileBase)child;
				switch (fb.base_type) {
					case "d": {
						var c = (OLLMfiles.Folder)child;
						var name = GLib.Path.get_basename(c.path);
						if (!metadata_keymap.has_key((int)c.id)) {
							folder_contents_lines += "  - (folder) " + name;
							break;
						}
						var vm = metadata_keymap.get((int)c.id);
						if (vm.description == "") {
							folder_contents_lines += "  - (folder) " + name;
							break;
						}
						folder_contents_lines += "  - (folder) " + name + ": " + vm.description;
						break;
					}
					case "fa": {
						var alias_fb = (OLLMfiles.FileBase)child;
						// Resolve alias target (FileBase.points_to nullable per libocfiles API). When null, do not try to fix; handle and break.
						if (alias_fb.points_to == null) {
							folder_contents_lines += "  - (alias) " + alias_fb.path;
							break;
						}
						var  fa_tag = (alias_fb.points_to is OLLMfiles.Folder)
								? "(alias->folder) " : "(alias->file) ";
						if (!metadata_keymap.has_key((int)alias_fb.points_to.id)) {
							folder_contents_lines += "  - " + 
								fa_tag + alias_fb.points_to.path;
							break;
						}
						if (metadata_keymap.get((int)alias_fb.points_to.id).description == "") {
							folder_contents_lines += "  - " + fa_tag + alias_fb.points_to.path;
							break;
						}
						folder_contents_lines += "  - " + fa_tag + alias_fb.points_to.path + ": " + metadata_keymap.get((int)alias_fb.points_to.id).description;
						break;
					}
					case "f": {
						var c = (OLLMfiles.File)child;
						var name = GLib.Path.get_basename(c.path);
						if (!metadata_keymap.has_key((int)c.id)) {
							folder_contents_lines += "  - (file) " + name;
							break;
						}
						var vm = metadata_keymap.get((int)c.id);
						if (vm.description == "") {
							folder_contents_lines += "  - (file) " + name;
							break;
						}
						folder_contents_lines += "  - (file) " + name + ": " + vm.description;
						break;
					}
					default:
						continue;
				}
			}
			// Build user message from template (joinv on empty array yields "")
			var user_message = cached_folder_template.fill(
				"folder_path", folder.path != "" ? folder.path : "unknown",
				"folder_contents",
					folder_contents_lines.length > 0 ?
						string.joinv("\n", folder_contents_lines) :
						"(no contents found)"
			);

			var messages = new Gee.ArrayList<OLLMchat.Message>();
			if (cached_folder_template.system_message != "") {
				messages.add(new OLLMchat.Message("system", cached_folder_template.system_message));
			}
			messages.add(new OLLMchat.Message("user", user_message));
			GLib.debug("Folder: %s", folder.path);
			string folder_description;
			try {
				folder_description = yield this.request_analysis(messages);
			} catch (GLib.Error e) {
				GLib.warning("Failed to analyze folder %s: %s", folder.path, e.message);
				folder_description = "";
			}

			var folder_metadata = new VectorMetadata() {
				element_type = "folder",
				element_name = GLib.Path.get_basename(folder.path),
				start_line = 0,
				end_line = 0,
				description = folder_description,
				file_id = folder.id,
				vector_id = 0,
				ast_path = ""
			};
			folder_metadata.saveToDB(this.sql_db, false);
			this.sql_db.backupDB();
			GLib.debug("Complete for %s: description length %d", folder.path, folder_description.length);
			return folder_metadata;
		}
	}
}
