# FileDropdown search returns rows but pulldown shows nothing

**Status:** OPEN — debug-first investigation

**Started:** 2026-07-04

**Process:** Follow **`docs/bug-fix-process.md`** — debug first with evidence, understand root cause, **then** propose a fix and wait for approval.

---

## Problem

Typing in the code editor **FileDropdown** search field triggers `Folder.fetch_files` RPC; results arrive (50 files for query `oll`) but the pulldown does not display rows.

**Expected:** After debounce, popup opens and lists matching files.

**Actual:** Popup appears empty or does not open; user sees no selectable rows.

---

## Reproduction

1. Open code editor with a project (e.g. `/home/alan/gitlive/OLLMchat`).
2. Focus the file dropdown search entry.
3. Type a non-empty query (e.g. `oll`).
4. Wait for debounce (~500 ms) and RPC reply.
5. Observe: no visible file rows in the pulldown.

**Run with `--debug`** so `GLib.debug()` reaches stderr.

---

## Evidence (2026-07-04)

```
send id=8 method=Folder.fetch_files … "query":"oll"
replied id=8 result_type=File array=true
search done text=oll filtered=50 list=50
```

RPC and client list model both have 50 items. No `popup show` line followed the search callback — **`base.set_popup_visible(true)` bypasses `FileDropdown` override** where earlier debug lived.

---

## Data flow

```
FileDropdown.on_entry_changed
  → debounced ProjectFiles.refresh(query)
  → Folder.fetch_files RPC
  → ProjectFiles.items_changed → FilterListModel
  → base.set_popup_visible(true)
  → SearchableDropdown.popup.popup()
  → Gtk.ListView bind (ProjectFile → label/icon)
```

**Key files:**

- `liboccoder/V2/FileDropdown.vala` — debounced search, popup override
- `liboccoder/SearchableDropdown.vala` — `set_popup_visible`, focus-leave close
- `libocfiles/V2/ProjectFiles.vala` — `refresh`, ListModel

---

## Hypotheses (unverified)

| Area | Why it might matter |
|------|---------------------|
| **`set_popup_visible` early return** | Already visible, `filtered==0` at call time, or widget not in toplevel |
| **Focus leave closes popup** | Entry loses focus when results arrive; popup hidden before paint |
| **List bind failure** | Wrong item type in factory bind (would log `bind item type=…`) |
| **Popup layout** | `FileDropdown` restructured popup child; zero-height scrolled area |
| **Race on refresh** | `refresh` clears items before repopulating; transient `filtered==0` |

---

## Debug added (2026-07-04)

| File | What it logs |
|------|----------------|
| `SearchableDropdown.vala` | `set_popup_visible`: unchanged / blocked (no_items, no_toplevel) / show / hide; entry focus leave |
| `V2/FileDropdown.vala` | After search refresh: show attempt + `popup.visible` after `base.set_popup_visible` |
| `V2/ProjectFiles.vala` | `refresh done` with query, total, loaded count |

**How to capture:** run app with `--debug`, grep for `popup`, `search show`, `refresh done`, `focus leave`, `bind item type`.

---

## Attempts / changelog

| Date | Change | Result |
|------|--------|--------|
| 2026-07-04 | Initial `search done` + `popup show` in FileDropdown override | Confirmed RPC + model counts; popup path still unknown |
| 2026-07-04 | Extended debug in SearchableDropdown + ProjectFiles + search callback | Pending user re-run |

---

## Conclusions

- **Root cause:** Unknown — model has 50 items; popup visibility / GTK bind / layout still unverified.
- **Next:** Re-run with new debug lines; record whether `popup show` or `popup blocked` / `focus leave` explains the empty UI.
