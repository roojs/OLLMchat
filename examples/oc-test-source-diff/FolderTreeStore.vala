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

/**
 * Folder rows for the file-selector tree.
 *
 * The top store owns the path map and the flat list of every folder.
 * Each folder's children are another {@link FolderTreeStore} for that
 * segment only. The same {@link OLLMfiles.Folder} sits in the segment,
 * the path map, and the flat list. The same maps remember the index
 * of each folder in its segment and in the flat list, so remove does
 * not scan. Add and remove go through the top store and signal
 * ''items-changed'' for that one position. There is no uuid map.
 * A notification does not clear the lists. Loading a different
 * project removes the rows already stored.
 * {@link load} puts the project on the top row, then asks the file
 * server once for every folder under it and appends any that are
 * not already stored. {@link loading} stays true while that one
 * request is waiting on the file server.
 *
 * == Example ==
 *
 * {{{
 * var store = new FolderTreeStore();
 * var root = new OLLMfiles.Folder(manager);
 * root.path = "/src";
 * store.append(null, root);
 * }}}
 */
class FolderTreeStore : Object, GLib.ListModel
{
	/**
	 * Top store. A child segment points at the store that owns the maps.
	 */
	public FolderTreeStore root { get; private set; }

	private Gee.ArrayList<OLLMfiles.Folder> items = new Gee.ArrayList<OLLMfiles.Folder>();

	/**
	 * Path to folder. Owned by the top store. Segments share the map.
	 */
	public Gee.HashMap<string, OLLMfiles.Folder> path_map {
		get; private set; default = new Gee.HashMap<string, OLLMfiles.Folder>();
	}

	/**
	 * Id to folder. Owned by the top store. Segments share the map.
	 */
	public Gee.HashMap<int, OLLMfiles.Folder> id_map {
		get; private set; default = new Gee.HashMap<int, OLLMfiles.Folder>();
	}

	/**
	 * Every folder, in the order they were added. Owned by the top store.
	 */
	public Gee.ArrayList<OLLMfiles.Folder> flat {
		get; private set; default = new Gee.ArrayList<OLLMfiles.Folder>();
	}

	/**
	 * Path to the child segment for that folder. Owned by the top store.
	 */
	public Gee.HashMap<string, FolderTreeStore> segments {
		get; private set; default = new Gee.HashMap<string, FolderTreeStore>();
	}

	/**
	 * Path to the index in that folder's segment. Owned by the top store.
	 */
	private Gee.HashMap<string, int> item_at = new Gee.HashMap<string, int>();

	/**
	 * Path to the index in {@link flat}. Owned by the top store.
	 */
	private Gee.HashMap<string, int> flat_at = new Gee.HashMap<string, int>();

	/**
	 * Paths already requested. Owned by the top store. Segments share it.
	 */
	public Gee.HashSet<string> loaded {
		get; private set; default = new Gee.HashSet<string>();
	}

	/**
	 * True while the one folder-tree request is waiting on the file
	 * server.
	 */
	public bool loading { get; private set; default = false; }

	private int pending = 0;

	/**
	 * Project path this tree is showing. Empty until a project loads.
	 */
	private string project_path = "";

	/**
	 * Generation of a project load. A switch drops the previous reply.
	 */
	private int load_epoch = 0;

	/**
	 * Top store. Child segments use {@link FolderTreeStore.child}.
	 */
	public FolderTreeStore()
	{
		Object();
		this.root = this;
	}

	/**
	 * Segment under one folder. Maps are the top store's maps.
	 *
	 * @param root Top store that owns the path map and the flat list
	 */
	public FolderTreeStore.child(FolderTreeStore root)
	{
		Object();
		this.root = root;
		this.path_map = root.path_map;
		this.id_map = root.id_map;
		this.flat = root.flat;
		this.segments = root.segments;
		this.loaded = root.loaded;
	}

	/**
	 * Item type for {@link GLib.ListModel}.
	 */
	public GLib.Type get_item_type()
	{
		return typeof(OLLMfiles.Folder);
	}

	/**
	 * Number of folders in this segment.
	 */
	public uint get_n_items()
	{
		return (uint) this.items.size;
	}

	/**
	 * Folder at ''position'' in this segment.
	 *
	 * @param position Zero-based index
	 * @return The folder, or null when ''position'' is past the end
	 */
	public Object? get_item(uint position)
	{
		if (position >= this.items.size) {
			return null;
		}
		return this.items.get((int) position);
	}

	/**
	 * Place ''folder'' under ''parent'', or on the top list when
	 * ''parent'' is null. A folder already stored at that path is left
	 * where it is. A child that has code or a document writes 1 into
	 * each parent whose count for that type is zero. The walk stops
	 * at the first parent that already has it, so a real count stays.
	 *
	 * @param parent Parent folder, or null for a top row
	 * @param folder Folder to attach
	 */
	public void append(OLLMfiles.Folder? parent, OLLMfiles.Folder folder)
	{
		if (this.root != this) {
			this.root.append(parent, folder);
			return;
		}
		if (this.path_map.has_key(folder.path)) {
			return;
		}
		var segment = this;
		if (parent != null) {
			if (!this.segments.has_key(parent.path)) {
				return;
			}
			segment = this.segments.get(parent.path);
		}
		this.segments.set(folder.path, new FolderTreeStore.child(this));
		this.path_map.set(folder.path, folder);
		this.id_map.set((int) folder.id, folder);
		this.flat_at.set(folder.path, this.flat.size);
		this.flat.add(folder);
		folder.parent = parent;
		/* 1 is a mark, not a file total. Stop at a parent that
		 * already has that type. Code and documents stop apart. */
		var need_document = folder.document_count > 0;
		var need_code = folder.code_count > 0;
		var above = parent;
		while (above != null && (need_document || need_code)) {
			need_document = above.document_count > 0 ? false : need_document;
			above.document_count = need_document ? 1 : above.document_count;
			need_code = above.code_count > 0 ? false : need_code;
			above.code_count = need_code ? 1 : above.code_count;
			above = above.parent;
		}
		var position = segment.items.size;
		this.item_at.set(folder.path, position);
		segment.items.add(folder);
		segment.items_changed((uint) position, 0, 1);
	}

	/**
	 * Detach ''folder'' from its segment, the path map, the id map,
	 * and the flat list.
	 *
	 * @param folder Folder to detach
	 */
	public void remove(OLLMfiles.Folder folder)
	{
		if (this.root != this) {
			this.root.remove(folder);
			return;
		}
		if (!this.item_at.has_key(folder.path)) {
			return;
		}
		var segment = this;
		if (folder.parent != null) {
			segment = this.segments.get(folder.parent.path);
		}
		var at = this.item_at.get(folder.path);
		var last = segment.items.size - 1;
		this.item_at.unset(folder.path);
		if (at != last) {
			var moved = segment.items.get(last);
			segment.items.set(at, moved);
			this.item_at.set(moved.path, at);
			segment.items_changed((uint) at, 1, 1);
		}
		segment.items.remove_at(last);
		segment.items_changed((uint) last, 1, 0);
		var flat_index = this.flat_at.get(folder.path);
		var flat_last = this.flat.size - 1;
		this.flat_at.unset(folder.path);
		if (flat_index != flat_last) {
			var moved_flat = this.flat.get(flat_last);
			this.flat.set(flat_index, moved_flat);
			this.flat_at.set(moved_flat.path, flat_index);
		}
		this.flat.remove_at(flat_last);
		this.path_map.unset(folder.path);
		this.id_map.unset((int) folder.id);
		this.segments.unset(folder.path);
		this.loaded.remove(folder.path);
		folder.parent = null;
	}

	/**
	 * Drop every folder. The top list emits one items-changed.
	 * The path map, the id map, the flat list, and the segment map
	 * are cleared.
	 */
	public void clear()
	{
		if (this.root != this) {
			this.root.clear();
			return;
		}
		var removed = this.items.size;
		this.items.clear();
		this.items_changed(0, (uint) removed, 0);
		this.flat.clear();
		this.path_map.clear();
		this.id_map.clear();
		this.segments.clear();
		this.item_at.clear();
		this.flat_at.clear();
		this.loaded.clear();
	}

	/**
	 * Fetch every folder under ''folder'' in one request and append
	 * the ones not already stored. The rows are sorted here by path,
	 * so a parent is appended before the folders inside it. A
	 * different project removes the rows already stored.
	 *
	 * @param folder Project, or a folder already in this store
	 */
	public async void load(OLLMfiles.Folder folder)
	{
		if (this.root != this) {
			yield this.root.load(folder);
			return;
		}
		if (folder.path == "") {
			return;
		}
		if (folder.is_project && !this.path_map.has_key(folder.path)
			&& this.project_path != folder.path) {
			this.load_epoch++;
			this.clear();
			this.project_path = folder.path;
		}
		if (this.project_path != "" && folder.path != this.project_path
			&& !folder.path.has_prefix(this.project_path + "/")) {
			return;
		}
		if (this.loaded.contains(folder.path)) {
			return;
		}
		if (folder.is_project && !this.path_map.has_key(folder.path)) {
			this.append(null, folder);
		}
		var epoch = this.load_epoch;
		this.loaded.add(folder.path);
		this.pending++;
		if (!this.loading) {
			this.loading = true;
		}
		/* Leave the read callback so the file pane can draw the
		 * spinner before this request.
		 */
		GLib.Idle.add(this.load.callback);
		yield;
		if (epoch != this.load_epoch) {
			this.pending--;
			if (this.pending == 0) {
				this.loading = false;
			}
			return;
		}
		OLLMrpc.Response response;
		try {
			response = yield folder.manager.rpc.call(new OLLMrpc.Request() {
				method = "Folder.fetch_children",
				args = OLLMrpc.args("s", folder.path)
			});
		} catch (GLib.Error e) {
			if (epoch != this.load_epoch) {
				this.pending--;
				if (this.pending == 0) {
					this.loading = false;
				}
				return;
			}
			this.loaded.remove(folder.path);
			this.pending--;
			if (this.pending == 0) {
				this.loading = false;
			}
			if (e.code == (int) OLLMrpc.RpcErrorCode.NOT_CONNECTED) {
				folder.manager.rpc.notification(new OLLMrpc.Notification() {
					method = "client.filesd.unreachable",
					id = e.code
				});
				return;
			}
			folder.manager.rpc.notification(new OLLMrpc.Notification() {
				method = "Banner.show",
				message = "Could not load folders: " + e.message
			});
			return;
		}
		if (epoch != this.load_epoch) {
			this.pending--;
			if (this.pending == 0) {
				this.loading = false;
			}
			return;
		}
		if (response.retval.type() != GLib.Type.INVALID) {
			var rows = (Gee.ArrayList<OLLMfiles.Folder>) response.retval.get_object();
			/* Row 0 is the folder this call asked for. The sort
			 * below can move it, so the loop skips that path.
			 */
			var incoming = rows.get(0);
			if (this.path_map.has_key(folder.path)) {
				folder.copy_from(incoming, {
					"manager",
					"children",
					"project-files",
					"parent",
					"points-to",
					"buffer"
				});
			}
			if (!this.path_map.has_key(folder.path)) {
				incoming.manager = folder.manager;
				this.append(folder.parent, incoming);
				folder = incoming;
			}
			rows.sort((a, b) => {
				return GLib.strcmp(a.path, b.path);
			});
			for (var i = 0; i < rows.size; i++) {
				if (epoch != this.load_epoch) {
					break;
				}
				var row = rows.get(i);
				if (row.path == "" || row.path == folder.path) {
					continue;
				}
				if (!this.id_map.has_key((int) row.parent_id)) {
					continue;
				}
				row.manager = folder.manager;
				this.append(this.id_map.get((int) row.parent_id), row);
			}
		}
		this.pending--;
		if (this.pending == 0) {
			this.loading = false;
		}
	}
}
