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

namespace OLLMfilesd
{
	/**
	 * libgit2-backed git provider for {@link Folder.read_dir} ignore checks.
	 */
	public class GitProvider : GitProviderBase
	{
		static construct
		{
			Ggit.init ();
		}

		public override void initialize ()
		{
			Ggit.init ();
		}

		public override void discover_repository (Folder folder)
		{
			try {
				var repo_file = Ggit.Repository.discover (
					GLib.File.new_for_path (folder.path));
				if (repo_file != null) {
					var repo = Ggit.Repository.open (repo_file);
					folder.set_data<Ggit.Repository> ("repo", repo);
				}
			} catch (GLib.Error e) {
				GLib.debug (
					"repository discover failed path=%s: %s",
					folder.path,
					e.message);
			}
		}

		public override bool path_is_ignored (
			Folder folder,
			string relative_path
		)
		{
			var repo = folder.get_data<Ggit.Repository> ("repo");
			if (repo == null) {
				return false;
			}

			try {
				return repo.path_is_ignored (relative_path);
			} catch (GLib.Error e) {
				GLib.debug (
					"path ignored check failed path=%s: %s",
					relative_path,
					e.message);
				return false;
			}
		}

		public override string? get_workdir_path (Folder folder)
		{
			var repo = folder.get_data<Ggit.Repository> ("repo");
			if (repo == null) {
				return null;
			}

			try {
				var workdir = repo.get_workdir ();
				return workdir?.get_path ();
			} catch (GLib.Error e) {
				GLib.debug (
					"workdir failed path=%s: %s",
					folder.path,
					e.message);
				return null;
			}
		}

		public override bool repository_exists (Folder folder)
		{
			var repo = folder.get_data<Ggit.Repository> ("repo");
			return repo != null;
		}
	}
}
