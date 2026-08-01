---
name: webpage-reader
description: This skill should be used when the user wants to read, fetch, extract, or analyze the content of a web page from a URL. Use when the user provides a URL to access documentation, articles, blog posts, research papers, release notes, or any online content and needs clean, readable content without navigation clutter.
license: MIT
---

## Purpose

Extract readable content from a web page URL using the **`browser`** tool. Prefer the main article/docs body; drop nav, ads, cookie chrome, and boilerplate when summarizing or saving notes.

## When to Use

Invoke this skill when:

- The user provides a URL and asks to "read", "fetch", "extract", or "get the content" of a page
- The user wants to analyze online documentation, API references, or technical guides
- The user shares a blog post, article, or research paper URL and needs the body content
- The user wants to save web content to a local Markdown file for offline reference or notes
- The agent needs to reference external content during a research or writing workflow

For multi-source research with citations, prefer `deep-research`. For PDFs or other binary formats, say the skill covers normal web pages and ask how the user wants to proceed.

## Workflow

### Step 1: Validate the Input

1. Verify HTTP/HTTPS URL; if needed, ask for a valid URL.
2. Raw `.md` URLs → open with `browser` and treat as Markdown.
3. Normal HTML pages → proceed with `browser`.
4. Multiple URLs → process sequentially; confirm count if many.

### Step 2: Fetch with `browser`

Open the URL with **`browser`** and take the page content (snapshot / readable text / markdown as the tool provides).

- Prefer the main content region when the tool returns structure.
- If the tool returns noisy chrome, strip obvious nav/footer lines in your reply or saved notes.
- On failure (403, 404, timeout, login wall): report clearly; retry once on timeout.

### Step 3: Deliver

- Default: return clean Markdown-oriented notes with the **source URL** at the top.
- If the user asked to save a file: `write` (or `edit`) under the path they named.
- Optional: short summary + key excerpts when the page is long.

### Step 4: Errors

| Situation | Response |
|-----------|----------|
| 403 Forbidden | Site blocks automated access; try manual open or another source |
| 404 Not Found | Verify URL |
| Timeout | Retry once; then report |
| Login / paywall | Ask user to paste content or authenticate |

## Remember

- Use **`browser`** for page content.
- Ask the user in chat when choices are needed.
- For multi-source synthesis, hand off to `deep-research`.

## Example Usage

1. "Read https://docs.example.com/api and summarize auth."
2. "Fetch this blog post and save notes to `notes/article.md`."
3. "Extract the release notes from this URL."
