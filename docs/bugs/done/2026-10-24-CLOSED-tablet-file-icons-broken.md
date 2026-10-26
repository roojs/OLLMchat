# File icons are broken on the tablet

**Status:** 🚫 CLOSED. History only. Closed with the follow-up on 25 Oct. That log is `docs/bugs/done/2026-10-25-CLOSED-tablet-file-icons-remaining.md`.

## Problem

- 🔷 On the tablet, the icons for files are broken. Every file row shows a missing-icon mark.
- 🔷 24 Oct, Pixel Tablet, source-diff app. The folder sheet itself opens.
- 🔷 The tablet build does not have the icon theme those names come from.

## Evidence

- ℹ️ The file grid binds `icon_name`. That name comes from `GLib.ContentType.get_generic_icon_name`, or `text-x-generic` when the guess is empty. `libocfiles/File.vala`. `examples/oc-test-source-diff/FileList.vala`.
- ℹ️ A `.vala` file is `text-x-generic`. A `.php` file is `text-x-script`. A `.png` file is `image-x-generic`. A `.md` file is `x-office-document`. None of those names end in `-symbolic`.
- ℹ️ `android/icons/manifest` is a curated Adwaita subset. It has `folder-symbolic` and `x-office-document-symbolic`. It has no `text-x-generic` and no `text-x-generic-symbolic`. `android/icons/Adwaita/index.theme` only lists symbolic directories plus the app icon.
- ℹ️ The host theme has the symbolic mime icons under `/usr/share/icons/Adwaita/symbolic/mimetypes/`. It has no `text-x-script-symbolic` and no `application-x-generic-symbolic`.

## Root cause

- ✔️ The grid asks for a full-color name. The tablet theme only contains the symbolic files listed in the manifest, and those mime icons were not listed.

## Proposed fix

- 🔷 Ask for the symbolic name when the full-color name is not in the theme. If that is missing too, use `text-x-generic-symbolic`.
- 🔷 Ship the Adwaita symbolic mime icons in the manifest. `x-office-document-symbolic` is already there.

### `examples/oc-test-source-diff/FileList.vala` — name bind

**Why:** `icon_name` is the full-color content-type name. The tablet theme can draw the symbolic one.

**Where:** The name factory bind, in place of the `icon-name` binding.

#### Replace with

```vala
				var icon = file.icon_name;
				var display = this.get_display();
				if (display == null) {
					display = Gdk.Display.get_default();
				}
				if (display != null) {
					var theme = Gtk.IconTheme.get_for_display(display);
					if (!theme.has_icon(icon) && !icon.has_suffix("-symbolic")) {
						icon = icon + "-symbolic";
					}
					if (!theme.has_icon(icon)) {
						icon = "text-x-generic-symbolic";
					}
				}
				((Gtk.Image) line.get_first_child()).icon_name = icon;
```

### `android/icons/manifest`

**Why:** The symbolic mime icons exist on the build host and were not packed.

**Where:** After the existing `x-office-document-symbolic` row.

#### Add

```text
symbolic/mimetypes/text-x-generic-symbolic.svg	Adwaita	symbolic/mimetypes/text-x-generic-symbolic.svg
symbolic/mimetypes/image-x-generic-symbolic.svg	Adwaita	symbolic/mimetypes/image-x-generic-symbolic.svg
symbolic/mimetypes/package-x-generic-symbolic.svg	Adwaita	symbolic/mimetypes/package-x-generic-symbolic.svg
symbolic/mimetypes/font-x-generic-symbolic.svg	Adwaita	symbolic/mimetypes/font-x-generic-symbolic.svg
symbolic/mimetypes/audio-x-generic-symbolic.svg	Adwaita	symbolic/mimetypes/audio-x-generic-symbolic.svg
symbolic/mimetypes/video-x-generic-symbolic.svg	Adwaita	symbolic/mimetypes/video-x-generic-symbolic.svg
symbolic/mimetypes/application-x-executable-symbolic.svg	Adwaita	symbolic/mimetypes/application-x-executable-symbolic.svg
```

The other symbolic mime files from that same directory are added with the same three columns.

## Next

- ✔️ 24 Oct. The language icons were on the device, and every file still drew the same document icon. The APK had no MIME database, so every name was `application/octet-stream`.
- 🚫 The grid must not hunt icon files, and it must not guess a type. The daemon sends `mime_type`.
- ✔️ 24 Oct. The name bind sets `icon_name` only. Install copies Humanity mime icons into `share/icons/hicolor/scalable/mimetypes`. The Android package ships that folder.
- 🔷 24 Oct, Pixel Tablet. The source-diff app dies a few seconds after the window appears.
- ℹ️ Relaunch on `emulator-5556`. Process `org.roojs.ollmchat.sourcediff` pid 6944, GTK thread 6962. `SIGSEGV` `SEGV_ACCERR` after about 8 seconds. 512 frames, all `real_choose_icon` in `gtkicontheme.c`.
- ✔️ `real_choose_icon` calls itself with `image-missing` when a name is absent (`gtkicontheme.c` around line 2143). That only ends when `image-missing` exists. GTK loads the first `icons/hicolor/index.theme` on the search path and skips the built-in index (`insert_theme`). The APK shipped `android/icons/hicolor/index.theme`, which lists only `scalable/mimetypes`. The built-in index is the one that includes `16x16/status`, where `image-missing.png` lives. With that directory dropped, the fallback never resolves and the lookup recurses until the stack dies.
- 🚫 Do not ship an `index.theme` for hicolor. The built-in index already lists `scalable/mimetypes`, so the copied SVGs are still found.

### `scripts/android/build-pixiewood-apk.sh` — hicolor staging

**Why:** A replacement hicolor index hides `image-missing`.

**Where:** The block that copies `android/icons/hicolor/index.theme`.

#### Remove

```bash
  local hicolor_index="$ROOT_DIR/android/icons/hicolor/index.theme"
  if [ ! -f "$hicolor_index" ]; then
    echo "Android hicolor index.theme missing: $hicolor_index" >&2
    exit 1
  fi
  mkdir -p "$assets_icons/hicolor"
  cp -a "$hicolor_index" "$assets_icons/hicolor/index.theme"
```

- ✔️ 24 Oct. The APK no longer ships `icons/hicolor/index.theme`. Reinstalled on the Pixel Tablet. The process was still running 15 seconds after launch, and the crash buffer was empty.
- ⏳ Install the new file daemon, then open a folder and check that Vala, C, and Python rows differ.
- 🔷 24 Oct, after that daemon was installed. Every file in the sheet still draws the same document icon.
- ✔️ `files.sqlite` for `/home/alan/gitlive/web.MediaOutreach`: all 37 direct children have `mime_type` `''`. `gio info` on the same tree is `application/x-php` for `crm.php` and `text/x-vala` for `FileList.vala`.
- ✔️ `Folder.read_dir_update` builds `new_item` with that type, then `copy_from` of the stored row copies every property except a short list. `mime-type` is not in the list, so the empty stored value replaces the type just read. `saveToDB` writes that empty value. The live row is also not given `mime_type`. The client then uses `text-x-generic` for every file.
- ✔️ The update now keeps `mime-type` the same way it already keeps `size` and `language`, and copies it onto the live row.

### `ollmfilesd/Folder.vala` — `read_dir_update`

**Why:** The scan's MIME type has to survive the merge with the stored row.

**Where:** The `copy_from` exception list, and the assignments onto `old_item`.

#### Replace with

```vala
			new_item.copy_from(old_item, {
				// except these...
				"manager", "path", "parent-id",
				"target-path", "base-type", "parent",
				"is-ignored", "is-repo",
				"is-text", "language", "size",
				"mime-type",
			});
```

```vala
			old_item.is_text = new_item.is_text;
			old_item.language = new_item.language;
			old_item.size = new_item.size;
			old_item.mime_type = new_item.mime_type;
```

- ✔️ Applied. Not on the running daemon until `/usr/bin/ollmfilesd` is replaced and the project is scanned again.
- 🔷 24 Oct. Some icons show. A type with no Humanity file draws a broken icon. The ones that show are too small. They should be about 50% bigger.
- ✔️ The grid image is `pixel_size = 16`. 50% bigger is 24. `Gtk.IconTheme.has_icon` only checks the scanned name list. It does not call `real_choose_icon`, so a missing name does not recurse into `image-missing`.
- ✔️ A missing name uses `text-x-generic`, which is one of the shipped SVGs.

### `examples/oc-test-source-diff/FileList.vala` — size and missing name

**Why:** A MIME name the theme does not have was left for GTK to draw as broken. The row icon is 16 pixels.

**Where:** The name factory setup sets the size. The bind picks the name.

#### Replace with

```vala
				line.append(new Gtk.Image() {
					pixel_size = 24,
				});
```

```vala
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

- ✔️ Applied in the file grid. Needs a new source-diff APK on the tablet.
- 🔷 24 Oct. MIME still looks random: some HTML and PHP rows have a type icon, some do not. JavaScript shows the old document square. `.bjs` shows a generic icon. The icons are still too small to read.
- ✔️ `text/javascript` becomes the icon name `text-javascript`. Humanity ships `text-x-javascript.svg`, not that name. GIO's own list for that type is `text-javascript`, then `text-x-script`. The grid only tried the first name, then `text-x-generic`, which is the plain document.
- ✔️ `application/xhtml+xml` has no Humanity file. GIO's next name is `text-html`, which is shipped. Those HTML rows are the ones without an HTML icon.
- ✔️ `.bjs` is Roo JSON. `shared-mime-info` stores it as `text/plain`, and `text-plain.svg` is the generic text icon. Language was not set for `.bjs`.
- ✔️ `Pman.Admin` is stored three times. The project row (`is_project=1`, id 16) has empty `mime_type` on every direct child. Two later rows of the same path (ids 1662 and 3444) were inserted when a symlink was scanned, and those children have MIME types. `web.MediaOutreach/Pman.Admin` points at 1662. Opening the project and opening the link therefore show different icons for the same files. Symlink rows themselves (`base_type=fa`) also keep an empty `mime_type`.
- ✔️ The alias update looked up `file_cache` with the symlink path, so it did not find the project and inserted another folder.

### `examples/oc-test-source-diff/FileList.vala` — icon name and size

**Why:** The MIME string is not always the Humanity file name, and 24 pixels is too small to read.

**Where:** The name factory setup sets the size. The bind picks a name the theme has.

#### Replace with

```vala
				line.append(new Gtk.Image() {
					pixel_size = 48,
				});
```

```vala
				var icon = file.icon_name;
				var display = this.get_display();
				if (display == null) {
					display = Gdk.Display.get_default();
				}
				if (display != null) {
					var theme = Gtk.IconTheme.get_for_display(display);
					var dash = icon.index_of("-");
					if (!theme.has_icon(icon) && dash > 0 && !icon.contains("-x-")) {
						var xform = icon.substring(0, dash) + "-x-" + icon.substring(dash + 1);
						if (theme.has_icon(xform)) {
							icon = xform;
						}
					}
					if (!theme.has_icon(icon) && file.mime_type != "") {
						var themed = GLib.ContentType.get_icon(file.mime_type) as GLib.ThemedIcon;
						if (themed != null) {
							foreach (var name in themed.names) {
								if (name.has_suffix("-symbolic")) {
									continue;
								}
								if (!theme.has_icon(name)) {
									continue;
								}
								icon = name;
								break;
							}
						}
					}
					if (!theme.has_icon(icon)) {
						icon = "text-x-generic";
					}
				}
				image.icon_name = icon;
```

### `ollmfilesd/File.vala` — `.bjs`

**Why:** Those files are JSON. The stored type `text/plain` can only draw the generic text icon.

**Where:** `File.new_from_info`, after the content type is read.

#### Add

```vala
			if (this.path.has_suffix(".bjs") &&
				(this.mime_type == "" || this.mime_type == "text/plain")) {
				this.mime_type = "application/json";
			}
```

### `ollmfilesd/Folder.vala` — one folder for a link target

**Why:** A symlink scan inserted a second folder, so the project row never received MIME types.

**Where:** `read_dir_update`, the alias `points_to` lookup. Prefer the project at that path, then the cache entry for the target path.

#### Replace with

```vala
				var known = this.manager.file_cache.get(new_item.target_path);
				if (old_item != null && old_item.target_path == new_item.target_path &&
					old_item.points_to != null) {
					known = old_item.points_to;
				}
				if (this.manager.projects.path_map.has_key(new_item.target_path)) {
					known = this.manager.projects.path_map.get(new_item.target_path);
				}
				if (known != null) {
					new_item.points_to = known;
					new_item.points_to_id = known.id;
					this.manager.file_cache.set(new_item.target_path, known);
				}
				if (known == null) {
					new_item.points_to.saveToDB(this.manager.db, null, false);
					new_item.points_to_id = new_item.points_to.id;
					if (new_item.points_to is Folder) {
						yield ((Folder) new_item.points_to).load_files_from_db();
					}
				}
				if (new_item.points_to.mime_type != "") {
					new_item.mime_type = new_item.points_to.mime_type;
				}
```

- 🚫 25 Oct. Applied, then removed. The icon-name rewrite, the 48-pixel size, the `.bjs` MIME override, and the link-target lookup are not acceptable. The fences above are the rejected proposals. The grid is back to 24 pixels and a single `text-x-generic` fallback. The daemon files are back to the scan that keeps `mime-type`.
- 🚫 25 Oct. Closed with the follow-up. Do not continue from this file.
