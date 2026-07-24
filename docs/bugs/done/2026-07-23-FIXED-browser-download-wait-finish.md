# Browser download waits until finish

**Status:** ✅ FIXED — user verified 2026-07-24

## Problem

- 🔷 `action: download` held the tool call open until the WebKit transfer **finished** (or failed).
- 🔷 A multi‑GB file would pin the agent for the whole download — unacceptable.
- 🔷 Expected: return as soon as the download **has started** (destination known / transfer underway). Progress and completion already go through activity notifications / GLib notifications.

## Evidence

- ℹ️ [`libocwebkit/Browser.vala`](../../libocwebkit/Browser.vala) `download()` connected `finished` / `failed` and `yield`ed until one fired.
- ℹ️ Destination is set earlier in `on_decide_destination` after Allow (`downloads_inflight[url] = dest`); progress/end already notify the agent.

## Root cause

- ✔️ Tool API waited for transfer completion instead of start.

## Fix applied

- ✔️ `Browser.download()` resumes when destination path is non‑empty (started) or on `failed` — not on `finished`.
- ✔️ Tool `@param` download text: returns once started; progress/completion via activity bar.

## Final

- Tool returns destination path once Allow + destination are set; activity bar still tracks progress/end.
