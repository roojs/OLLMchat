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

namespace OLLMvector2
{
	/**
	 * Vector building layer for code and documentation elements.
	 *
	 * Caller supplies element metadata, cached rows, and file line text —
	 * no File/Folder/Tree types in this library.
	 */
	public class VectorBuilder : Object
	{
		protected OLLMchat.Settings.Config2 config;
		protected Database database;
		protected SQ.Database sql_db;

		public VectorBuilder (
			OLLMchat.Settings.Config2 config,
			Database database,
			SQ.Database sql_db
		)
		{
			this.config = config;
			this.database = database;
			this.sql_db = sql_db;
			SQT.VectorMetadata.initDB (sql_db);
		}

		/**
		 * Incrementally vectorize code elements for one file.
		 */
		public async void process_elements (
			Gee.ArrayList<SQT.VectorMetadata> elements,
			Gee.HashMap<string, SQT.VectorMetadata> cached_metadata,
			string[] file_lines,
			string? debug_path = null
		) throws GLib.Error
		{
			if (elements.size == 0) {
				return;
			}

			var unchanged_elements = new Gee.ArrayList<SQT.VectorMetadata> ();
			var changed_elements = new Gee.ArrayList<SQT.VectorMetadata> ();
			var elements_to_delete = new Gee.HashSet<int> ();

			var current_keys = new Gee.HashSet<string> ();
			foreach (var element in elements) {
				current_keys.add (element.to_key ());
			}

			foreach (var element in elements) {
				var key = element.to_key ();

				if (!cached_metadata.has_key (key)) {
					changed_elements.add (element);
					continue;
				}

				var cached = cached_metadata.get (key);
				bool is_unchanged = false;

				if (element.vector_id > 0 && element.vector_id == cached.vector_id) {
					if (element.md5_hash != "" &&
						cached.md5_hash != "" &&
						element.md5_hash == cached.md5_hash) {
						is_unchanged = true;
					} else if (element.md5_hash == "" &&
							cached.md5_hash == "" &&
							element.element_name == cached.element_name &&
							element.element_type == cached.element_type) {
						is_unchanged = true;
					}
				}

				if (is_unchanged) {
					unchanged_elements.add (element);
				} else {
					changed_elements.add (element);
					if (cached.id > 0) {
						elements_to_delete.add ((int) cached.id);
					}
				}
			}

			foreach (var entry in cached_metadata.entries) {
				if (current_keys.contains (entry.key)) {
					continue;
				}
				if (entry.value.id > 0) {
					elements_to_delete.add ((int) entry.value.id);
				}
			}

			foreach (var id in elements_to_delete) {
				SQT.VectorMetadata.query (this.sql_db).deleteId ((int64) id);
			}

			foreach (var element in unchanged_elements) {
				var key = element.to_key ();
				if (!cached_metadata.has_key (key)) {
					continue;
				}

				var cached = cached_metadata.get (key);
				bool needs_update = false;

				if (cached.start_line != element.start_line || cached.end_line != element.end_line) {
					cached.start_line = element.start_line;
					cached.end_line = element.end_line;
					needs_update = true;
				}

				if (element.md5_hash != "" && cached.md5_hash == "") {
					cached.md5_hash = element.md5_hash;
					needs_update = true;
				}

				if (cached.description != element.description) {
					cached.description = element.description;
					needs_update = true;
				}

				if (needs_update) {
					cached.saveToDB (this.sql_db, false);
				}
			}

			if (changed_elements.size == 0) {
				return;
			}

			yield this.embed_and_store (
				changed_elements,
				(el) => format_element_document (el, file_lines, debug_path)
			);
		}

		/**
		 * Incrementally vectorize documentation leaf sections for one file.
		 */
		public async void process_documentation_elements (
			Gee.ArrayList<SQT.VectorMetadata> leaf_sections,
			Gee.HashMap<string, SQT.VectorMetadata> cached_metadata,
			string[] file_lines,
			string document_basename,
			string? document_summary = null
		) throws GLib.Error
		{
			if (leaf_sections.size == 0) {
				return;
			}

			var unchanged_elements = new Gee.ArrayList<SQT.VectorMetadata> ();
			var changed_elements = new Gee.ArrayList<SQT.VectorMetadata> ();
			var elements_to_delete = new Gee.HashSet<int> ();

			var current_keys = new Gee.HashSet<string> ();
			foreach (var element in leaf_sections) {
				current_keys.add (element.to_key ());
			}

			foreach (var element in leaf_sections) {
				var key = element.to_key ();

				if (!cached_metadata.has_key (key)) {
					changed_elements.add (element);
					continue;
				}

				var cached = cached_metadata.get (key);
				var element_content = lines_to_string (file_lines, element.start_line, element.end_line);
				var checksum = new GLib.Checksum (GLib.ChecksumType.MD5);
				checksum.update ((uint8[]) element_content.to_utf8 (), -1);
				element.md5_hash = checksum.get_string ();

				bool is_unchanged = false;

				if (element.vector_id > 0 && element.vector_id == cached.vector_id) {
					if (element.md5_hash != "" &&
						cached.md5_hash != "" &&
						element.md5_hash == cached.md5_hash) {
						is_unchanged = true;
					} else if (element.md5_hash == "" &&
							cached.md5_hash == "" &&
							element.element_name == cached.element_name &&
							element.element_type == cached.element_type) {
						is_unchanged = true;
					}
				}

				if (is_unchanged) {
					unchanged_elements.add (element);
					if (cached.start_line != element.start_line || cached.end_line != element.end_line) {
						cached.start_line = element.start_line;
						cached.end_line = element.end_line;
						cached.saveToDB (this.sql_db, false);
					}
				} else {
					changed_elements.add (element);
					if (cached.id > 0) {
						elements_to_delete.add ((int) cached.id);
					}
				}
			}

			foreach (var entry in cached_metadata.entries) {
				if (current_keys.contains (entry.key)) {
					continue;
				}
				if (entry.value.id > 0) {
					elements_to_delete.add ((int) entry.value.id);
				}
			}

			foreach (var id in elements_to_delete) {
				SQT.VectorMetadata.query (this.sql_db).deleteId ((int64) id);
			}

			if (changed_elements.size == 0) {
				return;
			}

			var chunk_metadata = new Gee.ArrayList<SQT.VectorMetadata> ();
			foreach (var section in changed_elements) {
				var section_content = lines_to_string (file_lines, section.start_line, section.end_line);
				chunk_metadata.add (create_chunk_metadata (section, section_content));
			}

			yield this.embed_and_store (
				chunk_metadata,
				(section) => {
					var content = lines_to_string (file_lines, section.start_line, section.end_line);
					return format_documentation_chunk (section, content, document_basename, document_summary);
				}
			);
		}

		/**
		 * Embed a single description and store one metadata row (e.g. image files).
		 */
		public async void add_single (
			int64 file_id,
			string element_type,
			string element_name,
			string description
		) throws GLib.Error
		{
			var existing = new Gee.ArrayList<SQT.VectorMetadata> ();
			SQT.VectorMetadata.query (this.sql_db).select (
				"WHERE file_id = %lld AND element_type = '%s'".printf (file_id, element_type),
				existing
			);

			var meta = existing.size > 0 ? existing.get (0) : new SQT.VectorMetadata () {
				file_id = file_id,
				element_type = element_type,
				element_name = element_name,
				description = description
			};

			meta.element_name = element_name;
			meta.description = description;

			var embeddings = yield this.database.embed_to_float_array ({ description });
			if (embeddings.rows == 0) {
				return;
			}

			meta.vector_id = (int64) this.database.vector_count;
			this.database.add_vectors_batch (embeddings);
			meta.saveToDB (this.sql_db, false);
		}

		private delegate string FormatDocument (SQT.VectorMetadata element);

		private async void embed_and_store (
			Gee.ArrayList<SQT.VectorMetadata> elements,
			FormatDocument format_document
		) throws GLib.Error
		{
			var documents = new string[elements.size];
			for (int i = 0; i < elements.size; i++) {
				documents[i] = format_document (elements.get (i));
			}

			var embeddings = yield this.database.embed_to_float_array (documents);
			if (embeddings.rows != elements.size) {
				throw new GLib.IOError.FAILED ("Embedding count mismatch");
			}

			int64 start_vector_id = (int64) this.database.vector_count;
			this.database.add_vectors_batch (embeddings);

			for (int j = 0; j < elements.size; j++) {
				var element = elements.get (j);
				element.vector_id = start_vector_id + j;
				element.saveToDB (this.sql_db, false);
			}
		}

		private string lines_to_string (string[] file_lines, int start_line, int end_line)
		{
			var sb = new GLib.StringBuilder ();
			int start_idx = start_line - 1;
			int end_idx = end_line - 1;
			for (int i = start_idx; i <= end_idx && i < file_lines.length; i++) {
				if (i >= 0) {
					sb.append (file_lines[i]);
				}
				if (i < end_idx) {
					sb.append ("\n");
				}
			}
			return sb.str;
		}

		private string format_element_document (
			SQT.VectorMetadata element,
			string[] file_lines,
			string? debug_path
		)
		{
			var doc = new GLib.StringBuilder ();

			doc.append_printf ("%s: %s\n", element.element_type, element.element_name);

			if (element.namespace != null && element.namespace != "") {
				doc.append_printf ("Namespace: %s\n", element.namespace);
			}

			if (element.parent_class != null && element.parent_class != "") {
				doc.append_printf ("Class: %s\n", element.parent_class);
			}

			var path = debug_path ?? "";
			doc.append_printf ("File: %s\nLines: %d-%d\n", path, element.start_line, element.end_line);

			if (element.signature != null && element.signature != "") {
				doc.append_printf ("Signature: %s\n", element.signature);
			}

			if (element.description != null && element.description != "") {
				doc.append_printf ("Description: %s\n", element.description);
			}

			if (element.element_type != "class" && element.element_type != "namespace") {
				doc.append ("Code:\n");
				doc.append (lines_to_string (file_lines, element.start_line, element.end_line));
			}

			return doc.str;
		}

		private string format_documentation_chunk (
			SQT.VectorMetadata section,
			string chunk_content,
			string document_basename,
			string? document_summary
		)
		{
			var doc = new GLib.StringBuilder ();
			doc.append_printf ("DOCUMENT: %s\n", document_basename);

			if (document_summary != null && document_summary.strip () != "") {
				doc.append_printf ("DOCUMENT SUMMARY: %s\n", document_summary.strip ());
			}

			var nesting_level = section.ast_path.split ("-").length;
			if (nesting_level > 1) {
				var section_context = section.get_section_context ();
				if (section_context != "") {
					doc.append_printf ("SECTION CONTEXT: %s\n", section_context);
				}
			}

			doc.append ("\n");
			doc.append (chunk_content);
			return doc.str;
		}

		private SQT.VectorMetadata create_chunk_metadata (SQT.VectorMetadata section, string chunk)
		{
			var chunk_meta = new SQT.VectorMetadata () {
				file_id = section.file_id,
				element_type = section.element_type,
				element_name = section.element_name,
				category = section.category,
				ast_path = section.ast_path,
				parent = section.parent,
				description = section.description,
				start_line = section.start_line,
				end_line = section.end_line
			};

			var checksum = new GLib.Checksum (GLib.ChecksumType.MD5);
			checksum.update ((uint8[]) chunk.to_utf8 (), -1);
			chunk_meta.md5_hash = checksum.get_string ();

			return chunk_meta;
		}
	}
}
