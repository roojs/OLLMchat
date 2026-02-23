---
name: research_topic
description: Use when you need to gather external information from the web (algorithms, libraries, best practices, troubleshooting) relevant to a coding task. Always follow this task with research_pages, which receives this task's output and summarizes the findings.
tools: web_search
---

## Research topic skill

Performs multiple web searches on a given topic.

### Input (this skill)

From the standard input, **What is needed** is what to research (the topic). The refinement step may pass a single **topic** (e.g. "async main loop Vala", "GLib.Source usage") as the focus for the web searches.

### Output (this skill)

Result summary and Detail. In Result summary: **summary of what this task did** to address the goal and **whether that answered it** (e.g. "Searched the web for Vala async; found official docs and samples — enough to proceed." or "Nothing relevant found."). Do not use a literal "Goal:" line. In Detail: use markdown links for sources (URLs from the search results); include short summaries about each reference and why it is useful. End with "Enough information to proceed." or "More research needed: [what to search next]."

### Instructions

#### Refinement

- Emit multiple **web_search** tool calls (up to ~5). Pass **query** from "What is needed" or the refined **topic**; use varied phrasings (e.g. main topic, plus "Vala", "GLib", "documentation", "example"). There is no "try again" at execution, so issue several queries in one refinement.

#### Execution (what to do with the results)

- Use the search output(s) from Precursor. For each search, note titles, snippets, and URLs; prefer authoritative sources (official docs, GNOME/Vala docs, reputable blogs).
- **Result summary**: one or two sentences — **what this task did** (e.g. what was searched, what was found) and **whether that answered the goal** (enough to proceed / nothing relevant). Summarise the work and outcome; do not start with "Goal:".
- **Detail**: single body or sub-sections with markdown links and short notes. End with "Enough information to proceed." or "More research needed: [suggest what to search next]."
- If no useful information is found across the searches, say so in Result summary (e.g. "Nothing relevant found.") and in Detail suggest alternative queries.

### Example

**Input:** `topic = "async method in Vala"`

**Output:**

## Result summary

Searched the web for Vala async; found official docs, GLib.MainLoop reference, and threading samples — enough to proceed.

## Detail

Vala supports async methods with `async`/`yield` and main-loop integration. Key sources: [Vala async documentation](https://wiki.gnome.org/Projects/Vala/AsyncMethods) (async/yield and main loop), [GLib.MainLoop](https://docs.gtk.org/glib/main-loop.html) (scheduling callbacks), [Vala threading](https://wiki.gnome.org/Projects/Vala/ThreadingSamples) (GLib.Thread and async).

Enough information to proceed.
