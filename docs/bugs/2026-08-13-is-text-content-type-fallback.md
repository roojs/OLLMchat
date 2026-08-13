# Extensionless / API-written files stay `is_text=0`

**Status:** ⏳ OPEN — root cause identified; fix not applied (await design/approval)

**Started:** 2026-08-13 · **Updated:** 2026-08-13

**Related:** [`2026-08-12-changed-files-notification-approvals-ui.md`](2026-08-12-changed-files-notification-approvals-ui.md) (Approvals click → `File.fetch` miss)

---

## Problem

🔷 Create a file **without an extension** via the API (e.g. `docs/Hello World Test` with plain text content).

**Expected:**
- Treated as a **text** file (`filebase.is_text = 1`)
- Appears in project file index / `project_files.child_map`
- Approvals (and editor) can `File.fetch` / open it like any other text file

**Actual:**
- DB row has **`is_text = 0`**, `language` empty, often `is_need_approval = 1`
- Excluded from `ProjectFiles.child_map` (only text files are added there)
- `File.fetch` looks up `child_map` only → **“file not found”** / empty result
- Approvals click does nothing useful even though the path is pending and on disk

---

## Evidence (2026-08-13)

✔️ Live `files.sqlite` for `/home/alan/gitlive/OLLMchat/docs/Hello World Test` (need-approval rows):

- `is_text = 0`, `language` empty, `is_need_approval = 1`
- File on disk exists (12 bytes, “Hello World”)

✔️ System / GIO say it **is** text:

```text
gio info …/docs/Hello World Test
  standard::content-type: text/plain
  standard::fast-content-type: application/octet-stream

file -bi …/docs/Hello World Test
  text/plain; charset=us-ascii
```

✔️ Client log on Approvals click: `File.fetch` sent and replied quickly; no editor open (fetch miss).

✔️ Code paths:

| Path | How `is_text` is set |
|------|----------------------|
| `File.new_from_info` (directory enum) | `FileInfo.get_content_type()` → `text/*`, or language from extension |
| `File.to_real` (API create / fake→real) | `detect_language()` from **extension only**; `is_text = true` **only if** `language != ""` |

→ Extensionless API writes never get `is_text` from content sniffing.

🚫 **Wrong fix (reverted):** make `File.fetch` fall back to `project_files.all_files` so non-text rows still open. That papers over bad `is_text` and leaves index/dropdown/vector paths wrong.

---

## Root cause

✔️ **`is_text` is not derived from system content-type on the API write / `to_real` path.**  
Extensionless files stay `is_text = 0` even when GIO/`file` would report `text/plain`. Downstream `child_map` / `File.fetch` then treat them as non-index text files.

---

## Hypotheses for the fix (not implemented)

💩 **H1 — On `to_real` / write (after bytes exist on disk):** `GLib.File.query_info(…, "standard::content-type")` (or equivalent) and set `is_text` from `text/*` (same rule as `new_from_info`). Optionally also set language when detect_language is empty but content is text.

💩 **H2 — Prefer sniff over fast-content-type:** `standard::fast-content-type` for extensionless is often `application/octet-stream`; full `standard::content-type` is `text/plain` for this file. Use the non-fast attribute (or `GLib.ContentType.guess` / read sample) so we do not trust the fast path alone.

💩 **H3 — Backfill:** one-off or migrate existing `is_need_approval=1` / openable files with `is_text=0` that sniff as text — optional after H1/H2.

---

## Proposed direction (await approval)

🔷 Fix **detection** at the source (`to_real` / write), matching `new_from_info`’s content-type rule, using **system/GIO content-type** (not fetch-layer workarounds).

🚫 Do not reopen by querying `all_files` in `File.fetch` as the product fix.

---

## Next

⏳ 🔷 Confirm sniff API choice (query_info content-type vs ContentType.guess + sample).

⏳ 🔷 Propose Remove/Replace/Add fences for `to_real` / write; apply after approval.

⏳ Re-test: write extensionless Hello World → `is_text=1` → in `child_map` → Approvals click opens.
