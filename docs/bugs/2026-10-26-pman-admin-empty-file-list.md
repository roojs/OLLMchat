# Pman.Admin file list is empty after Web Media Outreach

**Status:** ✔️ daemon reply checked. UI not opened.

## Problem

- 🔷 26 Oct, desktop and tablet, source-diff app. Open Web Media Outreach, then Pman.Admin. The right-hand file list is empty.
- 🔷 Expected: the files in that folder are listed.
- ℹ️ Restarting the 08:15 daemon did not change it. That process already had the `path_map` lookup from `docs/bugs/done/2026-10-25-CLOSED-pman-admin-files-loading.md`.

## Evidence

- ✔️ 08:15 session, daemon pid 267874, `/usr/bin/ollmfilesd`. Client opens `/home/alan/gitlive/web.MediaOutreach`. `Folder.fetch_dir` id 7 returns rows. id 8 returns none.
- ✔️ The empty reply is `OLLMrpc.val` on a zero-length list: daemon log `type id '0' is invalid` immediately after `recv id=8 method=Folder.fetch_dir`.
- ✔️ `files.sqlite` has 115 direct files under `/home/alan/gitlive/Pman.Admin` on the project row id 16, and the same count on the link-target row id 1662. The alias `/home/alan/gitlive/web.MediaOutreach/Pman.Admin` (id 1663) points at 1662.
- ✔️ `read_dir_update` points that alias at `path_map` (id 16) because the path is a project. It only called `load_files_from_db` when `points_to.id == 0`. Id 16 is not 0, so the project object kept an empty `children` list. `fetch_dir` then listed that object.

## Root cause

- ✔️ The file list is the in-memory children of the project folder. Opening Web Media Outreach retargets the Pman.Admin link at that project and does not load it. `fetch_dir` replies with those empty children.

## Proposed fix

- 🔷 `fetch_dir` loads the folder from the database when it is a stored folder with no children in memory, then replies.
- 🔷 `read_dir_update` loads a folder link target whose children are empty, including a project the alias was just pointed at.

### `ollmfilesd/Folder.vala` — `fetch_dir`

**Why:** The reply walks `folder.children`. That list is empty until `load_files_from_db` runs on this object.

**Where:** `fetch_dir`, after the missing-folder reply.

#### Replace with

The method replies from a local function. That function runs immediately when children are already loaded. Otherwise it runs from the `load_files_from_db` callback.

### `ollmfilesd/Folder.vala` — `read_dir_update`

**Why:** The alias is pointed at the project before `update_from` copies it into the linking project's map. Loading here fills the same object `fetch_dir` will list.

**Where:** The `points_to.id == 0` block. The save stays. The load runs whenever the target is a folder with no children.

## Attempts

- ✔️ Applied both edits in `ollmfilesd/Folder.vala`.
- ✔️ Installed `/usr/bin/ollmfilesd` is the 08:26 binary, pid 277239.
- ✔️ A copy of `files.sqlite` was asked, through that binary, for `Folder.fetch_dir` on `/home/alan/gitlive/Pman.Admin` before and after `ProjectManager.rpc_activate_project` of `/home/alan/gitlive/web.MediaOutreach` with the filesystem scan. Both replies are `msg=115`. Web Media Outreach itself replies `msg=23`.
