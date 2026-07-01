/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMfilesd
{
	/** {@code Daemon.*} request params. */
	public class DaemonParams : OLLMrpc.CallParam
	{
		public int protocol { get; set; default = 0; }
		public string client { get; set; default = ""; }
	}

	/** {@code ProjectManager.*} request params. */
	public class ProjectParams : OLLMrpc.CallParam
	{
		public string path { get; set; default = ""; }
		public bool skip_scan { get; set; default = false; }
		public bool project_summary_only { get; set; default = false; }
	}

	/** {@code File.*} request params. */
	public class FileParams : OLLMrpc.CallParam
	{
		public string path { get; set; default = ""; }
		public string project_path { get; set; default = ""; }
		public string content { get; set; default = ""; }
		/** {@code f} file, {@code d} directory, {@code fa} symlink ({@link File.write}). */
		public string base_type { get; set; default = "f"; }
		/** Symlink target when {@code base_type == "fa"} ({@code File.write}). */
		public string target { get; set; default = ""; }
		/** Optional rwx ({@code 0777}) applied after the write op. */
		public uint unix_mode { get; set; default = 0; }
		public bool buffer_dirty { get; set; default = false; }
		public int64 last_known_mtime { get; set; default = 0; }
		/** {@link FileHistory.approve} / {@link FileHistory.revert} — {@code file_history.id}. */
		public int64 id { get; set; default = 0; }
	}

	/** {@code Folder.*} request params (project-scoped). */
	public class FolderParams : OLLMrpc.CallParam
	{
		public string project_path { get; set; default = ""; }
		public string path { get; set; default = ""; }
		/** {@link Folder.fetch_files} — skip rows (default 0). */
		public int offset { get; set; default = 0; }
		/** {@link Folder.fetch_files} — page size (default 50). */
		public int limit { get; set; default = 50; }
		/** {@link Folder.fetch_files} — dropdown filter (default browse all). */
		public string query { get; set; default = ""; }
		/** {@link Folder.fetch_files} — paths to look up (empty = dropdown paged mode). */
		public string[] paths { get; set; default = new string[] {}; }
		/** {@link Folder.fetch_files} — index row only; no buffer (path-filter batch). */
		public bool metadata_only { get; set; default = false; }
	}

	/** {@code vector.*} request params. */
	public class VectorParams : OLLMrpc.CallParam
	{
		public string path { get; set; default = ""; }
		public string query { get; set; default = ""; }
		public int max_results { get; set; default = 0; }
		public string language { get; set; default = ""; }
		public string element_type { get; set; default = ""; }
		public string category { get; set; default = ""; }
		public string only_file { get; set; default = ""; }
		public string format { get; set; default = ""; }
		public string file_path { get; set; default = ""; }
		public string ast_path { get; set; default = ""; }
	}
}
