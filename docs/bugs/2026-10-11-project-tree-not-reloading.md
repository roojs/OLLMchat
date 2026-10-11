# Project tree stays on the previous project

**Status:** ⏳ Root cause confirmed. Fix is in `FolderTreeStore.load`. Not yet checked by flipping projects in the window.

## Problem

- 🔷 Open a project, then another, then the first one again. The folder tree does not come back.
- 🔷 Seen with Paymal admin, then back to OLLMchat. The OLLMchat tree is not shown.

## Evidence

- ✔️ `examples/oc-test-source-diff/FolderTreeStore.vala` `load`.
- ✔️ The different-project return ran before the block that drops the stored rows and sets `project_path`.
- ✔️ A project path is not a child of the previous project, so that return always left the previous tree in place.
- ✔️ `loaded` still held the first project, so a later visit returned again at `loaded.contains` and did not fetch.

## Root cause

- ✔️ Switching projects never reached the clear. The guard treated the newly chosen project as a stale folder and returned.

## Proposed fix

**Why:** The chosen project has to replace the stored rows before the guard drops folders that are not under it.

**Where:** `examples/oc-test-source-diff/FolderTreeStore.vala` `load`, the two checks after the empty-path return.

#### Remove

```vala
		if (this.project_path != "" && folder.path != this.project_path
			&& !folder.path.has_prefix(this.project_path + "/")) {
			return;
		}
		if (folder.is_project && !this.path_map.has_key(folder.path)
			&& this.project_path != folder.path) {
			this.load_epoch++;
			while (this.flat.size > 0) {
				this.remove(this.flat.get(this.flat.size - 1));
			}
			this.loaded.clear();
			this.project_path = folder.path;
		}
```

#### Replace with

```vala
		if (folder.is_project && !this.path_map.has_key(folder.path)
			&& this.project_path != folder.path) {
			this.load_epoch++;
			while (this.flat.size > 0) {
				this.remove(this.flat.get(this.flat.size - 1));
			}
			this.loaded.clear();
			this.project_path = folder.path;
		}
		if (this.project_path != "" && folder.path != this.project_path
			&& !folder.path.has_prefix(this.project_path + "/")) {
			return;
		}
```

## Next

- 🔷 ⏳ Flip Paymal admin to OLLMchat and back in the smoke app and confirm each tree appears.
