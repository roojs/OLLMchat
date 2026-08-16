# Approvals list click does not show Approve / Reject

**Status:** ✅ FIXED — user verified 2026-08-15 (Approve / Reject show; approval flow works)

**Started:** 2026-08-15

**Related:** [`2026-08-12-FIXED-changed-files-notification-approvals-ui.md`](2026-08-12-FIXED-changed-files-notification-approvals-ui.md) (list populate / open file)

---

## Problem

🔷 After loading the app, hover the changed-files (task-due) icon: **Hello World** is in the dropdown. Click it: the file is **already loaded** in the editor. **Approve / Reject never appear.**

🔷 If the file were already approved, it should **not** be on the changed list.

---

## Evidence

ℹ️ Window restore file (`config.2.json`): `/home/alan/gitlive/OLLMchat/docs/Hello World Test`

✔️ Live client log `~/.cache/ollmchat/ollmchat.debug.log` (startup 08:02:32, user report ~08:04):

- `Folder.fetch_pending_approvals` **id=5** replies at 08:02:32.288 — pending list filled first
- `File.fetch` **id=7** replies at 08:02:34.468 — restored Hello World **after** the list exists
- No further Approvals / `File.fetch` around the click (08:04) — click did not go through `update_selected_file` → `file_selected`

✔️ SQLite `files.sqlite` — **not** already approved:

- Two `filebase` rows for the same path, both `is_need_approval=1`, `last_change_type=added` (ids 110749, 110750)
- Matching `file_history` status=0, `approve_id` 370 / 371
- Pending SQL would return those rows (list membership is correct)

ℹ️ Duplicate `filebase` rows for one path is a separate mess (list can show the name twice). Not this click bug.

ℹ️ Approve / Reject visibility is only `selected_file != null` in `update_button_visibility()` (`liboccoder/Approvals.vala`). Programmatic `select_file()` / `clear_selection()` never call that method.

---

## Root cause

✔️ Restoring the last open file calls `activate_file` → `on_active_file_changed` → `select_file()` because the path is already in `review_files.file_map`.

✔️ `select_file()` sets `selection.selected` and `selected_file` with `blocking_selection_handler = true`, so `update_selected_file()` does **not** run. It never calls `update_button_visibility()`, so Approve / Reject stay hidden.

✔️ The dropdown row is **already selected**. A second click on that same row does not emit `selection_changed`, so the click path that *does* show the buttons never runs. The editor looks “currently loaded” because session restore already opened the file (`AgentPi.Factory` → `apply_manager_state` → `open_file`).

🚫 Not “already approved, leftover on the list” for this Hello World file.

---

## Proposed fix

🔷 Show Approve / Reject whenever the selected pending row is set programmatically (restore / active-file sync), not only on a list-click `selection_changed`.

💩 Optional extra (not required if §1–§2 land): `ListView.single_click_activate` + `activate` so a click on the already-selected row still runs `update_selected_file`. In-tree pattern: `liboccoder/SearchableDropdown.vala`. Skip unless click-on-selected still fails after §1–§2.

### 1. `liboccoder/Approvals.vala` — `select_file`: show buttons after programmatic select

**Why:** Restore / `on_active_file_changed` selects the pending row without going through `update_selected_file`.

**Where:** end of `select_file`, after `blocking_selection_handler = false`.

**Depends on:** none.

#### Remove
```vala
			this.blocking_selection_handler = false;
		}
```

#### Replace with
```vala
			this.blocking_selection_handler = false;
			this.update_button_visibility();
		}
```

### 2. `liboccoder/Approvals.vala` — `clear_selection`: hide buttons when selection cleared

**Why:** Same method pair; leaving `selected_file = null` without refreshing visibility is the inverse bug.

**Where:** end of `clear_selection`, after `blocking_selection_handler = false`.

**Depends on:** none.

#### Remove
```vala
			this.blocking_selection_handler = false;
		}
```

#### Replace with
```vala
			this.blocking_selection_handler = false;
			this.update_button_visibility();
		}
```

Apply this **Replace with** only to `clear_selection` (the `unselect_all` method), not to `select_file` (already covered in §1). Both methods currently end with the same two lines; match on `unselect_all` / `selected_file = null` in `clear_selection`.

### 3. `liboccoder/Approvals.vala` — `refreshed`: if the open file is pending, select it

**Why:** Opposite startup order (activate file before pending RPC) currently `clear_selection`s then never re-selects after the list fills.

**Where:** `review_files.refreshed` handler in the constructor; replace the `selected_file == null` early return.

**Depends on:** §1 (`select_file` must update visibility).

#### Remove
```vala
			this.project_manager.review_files.refreshed.connect(() => {
				this.update_button_visibility();
				if (this.selected_file == null) {
					return;
				}
				if (!this.project_manager.review_files.file_map.has_key(
					this.selected_file.path
				)) {
					this.clear_selection();
				}
			});
```

#### Replace with
```vala
			this.project_manager.review_files.refreshed.connect(() => {
				this.on_active_file_changed(this.project_manager.active_file);
			});
```

---

## Attempts / changelog

- ✔️ 2026-08-15 — User smoke: list shows Hello World; click does not show Approve/Reject; file already open.
- ✔️ 2026-08-15 — DB: still `is_need_approval=1`; not an approved leftover.
- ✔️ 2026-08-15 — Live RPC order: pending fetch before restored `File.fetch`; no click-time `File.fetch`.
- ✔️ 2026-08-15 — User approved programmatic select → `update_button_visibility`; applied §1–§3.
- ✔️ 2026-08-15 — §3 rewritten: no `active` alias / nested null check / chopped `has_key`; `refreshed` calls `on_active_file_changed`.

## Next

✅ Closed 2026-08-15 — user verified Approve / Reject show without a list click.
