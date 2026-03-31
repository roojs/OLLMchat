---
name: research_online_search
description: Use when you need to gather external information from the web (algorithms, libraries, best practices, troubleshooting) relevant to a coding task. Refinement emits web searches; execution analyzes the single combined output and recommends pages to look at. Follow with research_web_page to fetch and analyze those pages.
tools: web_search
---

**During refinement**

**Purpose of this skill:** Gather external information from the web; the executor needs the search results so it can analyze them and recommend pages to look at. Refinement fills in **References** so the executor can deliver what is needed, and emits the web searches.

You receive **what is needed** for this task and a **summary of the task list so far executed** (including output summaries from previous tasks). Fill in **References** so the executor can deliver what is needed. **Encourage multiple searches — up to 5.** Emit multiple **web_search** tool calls. Use **query** from "What is needed" or a refined **topic**; use varied phrasings (e.g. main topic, plus "Vala", "GLib", "documentation", "example"). There is no "try again" at execution, so issue several queries in one refinement. **Avoid whole files** in References — add **code sections** or **references to parts of a task output** (e.g. file + section/method/snippet) rather than full file contents.

---

**At execution you do not run searches.** You only interpret. You receive a **single output** (the combined search results from the refinement tool calls). Output **only** a **## Result summary** — no other sections.

- Prefer authoritative sources (official docs, GNOME/Vala docs, reputable blogs).
- **Be strict about relevance.** Only list a result if it is **clearly relevant** to the search and **likely to help** achieve the task aims. Do **not** assume; if a result is tangential, off-topic, or unlikely to help, **do not mention it** in the list — including weak results will confuse downstream tasks and waste time. Be **explicit** when a result is **not** relevant: either omit it or state briefly that you are excluding it (e.g. "X was not relevant to [aim]").
- **Result summary**: Say what you searched for and what you found. **Highlight specific pages and what each tells you** — not just the page title. For each **relevant** result only: link + short description of what it contains (e.g. "[Documentation for GLib.MainLoop](url) — describes scheduling callbacks and main-loop integration; [Vala async](url) — async/yield and main loop."). Recommend pages worth fetching with **research_web_page** for full context. If enough to proceed, say so; if more research needed, say what to search next.
- **If nothing relevant was found:** Say so clearly: "We searched for [topic] but did not find anything relevant." Do not add a body section or suggest alternative queries in that case unless useful.

### Example output (found relevant results)

## Result summary

Searched the web for Vala async. Found: [Vala async documentation](https://wiki.gnome.org/Projects/Vala/AsyncMethods) — async/yield and main loop; [Documentation for GLib.MainLoop](https://docs.gtk.org/glib/main-loop.html) — scheduling callbacks and main-loop integration; [Vala threading](https://wiki.gnome.org/Projects/Vala/ThreadingSamples) — GLib.Thread and async. Enough to proceed. Recommend fetching the first two with research_web_page for full context.

### Example output (nothing relevant)

## Result summary

We searched for [obscure Vala API X] but did not find anything relevant.
