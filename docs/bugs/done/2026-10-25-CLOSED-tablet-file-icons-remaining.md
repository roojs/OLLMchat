# File icons still wrong on the tablet

**Status:** 🚫 CLOSED. Icons are good enough. Left as they are on 25 Oct.

ℹ️ History of the earlier attempts is in `docs/bugs/done/2026-10-24-CLOSED-tablet-file-icons-broken.md`.

## Problem

- 🔷 Some HTML and PHP rows show a type icon. Others in the same sheet show the plain document.
- 🔷 JavaScript shows the plain document. The JavaScript icon is a coffee cup.
- 🔷 `.bjs` shows the generic text icon.
- 🔷 The icons that do show are too small to read. 24 pixels is the current size.

## Evidence

- ✔️ The grid sets `icon_name` from the daemon MIME type, with `/` turned into `-`. A name the theme does not have becomes `text-x-generic`. `examples/oc-test-source-diff/FileList.vala`. The image is `pixel_size = 24`.
- ✔️ `text/javascript` asks for `text-javascript`. Humanity ships `text-x-javascript.svg`. GIO's list for that type is `text-javascript`, then `text-x-script`.
- ✔️ `application/xhtml+xml` has no Humanity file. GIO's next name is `text-html`, which is shipped. `application/x-php` matches `application-x-php.svg`.
- ✔️ `.bjs` is Roo JSON. shared-mime-info stores it as `text/plain`. `text-plain.svg` is the generic text icon. `ollmfilesd/BufferProviderBase.vala` maps the extension to the json language. The stored MIME type is still `text/plain`.
- ✔️ A real `.php` file can have `application/x-php`. A symlink row (`base_type` `fa`) keeps an empty `mime_type`, so it draws the plain document.
- ✔️ `GLib.ContentType.get_icon` for `text/javascript` returns `text-javascript`, then `text-x-script`, then those two names with `-symbolic` added. Humanity ships `text-x-script.svg`. It does not ship `text-javascript.svg`. `text-x-javascript.svg` is a link to `text-x-java-source.svg`, the coffee cup. That name is not in the list.
- ✔️ `application/xhtml+xml` has generic icon `text-html`. That file is shipped. `application/x-php` has `application-x-php.svg`, which is a link to `text-html.svg`.
- ✔️ The name bind runs on a row inside the window. `get_display()` is that window's display.
- ✔️ `Pman.Admin` is stored three times. The project row (id 16, `is_project=1`) has an empty `mime_type` on every direct child. Two later rows of the same path (ids 1662 and 3444) were inserted when a symlink was scanned, and those children have types. `web.MediaOutreach/Pman.Admin` points at 1662. Opening the project and opening the link show different icons for the same files.

## Root cause

- ✔️ The icon name is the MIME string with the slash replaced. That name is often not the Humanity file name, so the row falls through to the plain document.
- ✔️ Symlink rows do not store the target's MIME type. A scan of a symlink also inserted a second folder instead of updating the project row, so one copy of a folder has types and the other does not.
- ✔️ `.bjs` stays `text/plain`, which has a generic icon.

## Proposed fix

- 🚫 Do not search the theme. `get_icon` lists the mime name, the generic name, and those two names again with `-symbolic`. The symbolic pair is the same two icons. The grid already has the mime name. The generic name is `GLib.ContentType.get_generic_icon_name`.
- 🚫 Do not treat `get_display()` as null. The bind runs on a row in the window.
- 🚫 Do not ask for `text-x-javascript`. That file is the Java source icon. `text/javascript` does not name it.
- 🚫 Do not put `get_generic_icon_name` on a ternary arm. Vala can free that temporary before the copy. Call it once into a local, then use the local. `examples/oc-vala-ternary-bug.vala`.
- 💩 48 pixels. When the mime name is absent, use the generic name for that type. When that file is also absent, use `text-x-generic`.
- 💩 `.bjs` is already `json` in the extension map. That language maps to `application/json` before the text flag is set. A suffix check in `File.new_from_info` is the wrong place.
- 💩 A symlink scan must use the folder already stored at the target path. The project at that path wins. The link row takes the target's MIME type.

### `examples/oc-test-source-diff/FileList.vala` — size

**Why:** 24 pixels is too small to read.

**Where:** Class comment, and the name factory setup.

#### Remove

```vala
	 * daemon MIME type. The theme draws that name at 24 pixels. A
	 * name it does not have uses ''text-x-generic''. The name column
```

#### Replace with

```vala
	 * daemon MIME type. The theme draws that name at 48 pixels. A
	 * name it does not have uses the generic icon for that type,
	 * then ''text-x-generic''. The name column
```

#### Remove

```vala
				line.append(new Gtk.Image() {
					pixel_size = 24,
				});
```

#### Replace with

```vala
				line.append(new Gtk.Image() {
					pixel_size = 48,
				});
```

### `examples/oc-test-source-diff/FileList.vala` — `name_factory.bind`

**Why:** The mime name is often not a Humanity file. The generic name for that type is. JavaScript then uses `text-x-script`. XHTML uses `text-html`.

**Where:** The bind, in place of the display check and the `text-x-generic` assignment.

#### Remove

```vala
				var image = (Gtk.Image) line.get_first_child();
				var icon = file.icon_name;
				var display = this.get_display();
				if (display == null) {
					display = Gdk.Display.get_default();
				}
				if (display != null &&
					!Gtk.IconTheme.get_for_display(display).has_icon(icon)) {
					icon = "text-x-generic";
				}
				image.icon_name = icon;
```

#### Replace with

```vala
				var icon = file.icon_name;
				if (!Gtk.IconTheme.get_for_display(this.get_display()).has_icon(icon)) {
					var generic = GLib.ContentType.get_generic_icon_name(file.mime_type);
					icon = generic != null ? generic : "text-x-generic";
				}
				if (!Gtk.IconTheme.get_for_display(this.get_display()).has_icon(icon)) {
					icon = "text-x-generic";
				}
				((Gtk.Image) line.get_first_child()).icon_name = icon;
```

### `ollmfilesd/BufferProviderBase.vala` — extension map

**Why:** `.bjs` is already `json` in the extension map. The MIME type belongs in that same list. `File.new_from_info` calls `detect_language` before it sets `is_text`.

**Where:** `init_extension_map`, beside the `bjs` row. `detect_language`, after the language id is read.

#### Add

Beside `extension_map.set("bjs", "json")`. `json` uses `application/json` when the scan left `text/plain` or an empty type.

```vala
			mime_map.set("json", "application/json");
```

#### Add

In `detect_language`, after `extension_map.get` returns a language. Replaces `text/plain` or an empty type with the mapped MIME type.

```vala
			var mapped = mime_map.get(lang);
			if (mapped != null &&
					(file.mime_type == "" || file.mime_type == "text/plain")) {
				file.mime_type = mapped;
			}
```

### `ollmfilesd/Folder.vala` — `read_dir_update`

**Why:** The lookup used the symlink path, so the project at the target path was missed and a second folder was inserted. The link row also kept an empty type.

**Where:** The `FileAlias` branch that assigns `points_to`.

#### Remove

```vala
			if (new_item is FileAlias && new_item.points_to_id > -1
				&& new_item.points_to != null) {
				
				if (old_item != null && old_item.target_path == new_item.target_path) {
					new_item.points_to = old_item.points_to;
					new_item.points_to_id  = old_item.points_to_id;
				} else if (this.manager.file_cache.has_key(new_item.path)) {
					new_item.points_to = this.manager.file_cache.get(new_item.path);
					new_item.points_to_id = new_item.points_to.id;
					// do we need to do anything?
					// i dont think so - the recursive code should handle it.
				} else {
					// it really does not exist.
					new_item.points_to.saveToDB(this.manager.db, null,false);
					new_item.points_to_id = new_item.points_to.id;
					if (new_item.points_to is Folder) { 
						yield ((Folder)new_item.points_to).load_files_from_db();
					}
				}
			}
```

#### Replace with

```vala
			if (new_item is FileAlias && new_item.points_to_id > -1 &&
					new_item.points_to != null) {
				if (this.manager.projects.path_map.has_key(new_item.target_path)) {
					new_item.points_to = this.manager.projects.path_map.get(new_item.target_path);
					new_item.points_to_id = new_item.points_to.id;
				}
				if (new_item.points_to.id == 0 &&
						this.manager.file_cache.has_key(new_item.target_path)) {
					new_item.points_to = this.manager.file_cache.get(new_item.target_path);
					new_item.points_to_id = new_item.points_to.id;
				}
				if (new_item.points_to.id == 0 &&
						old_item != null &&
						old_item.target_path == new_item.target_path) {
					new_item.points_to = old_item.points_to;
					new_item.points_to_id = old_item.points_to_id;
				}
				if (new_item.points_to.id == 0) {
					new_item.points_to.saveToDB(this.manager.db, null, false);
					new_item.points_to_id = new_item.points_to.id;
					if (new_item.points_to is Folder) {
						yield ((Folder) new_item.points_to).load_files_from_db();
					}
				}
				new_item.mime_type = new_item.points_to.mime_type;
			}
```

## Next

- ✔️ 25 Oct. Applied in `FileList.vala`, `ollmfilesd/File.vala`, and `ollmfilesd/Folder.vala`.
- ✔️ 25 Oct. Source-diff APK installed on the Pixel Tablet (`emulator-5556`). Process `org.roojs.ollmchat.sourcediff` pid 28931 was still running 15 seconds after launch. Crash buffer empty.
- 🚫 25 Oct. Closed by request. The remaining mismatches stay. The host daemon was not replaced.
