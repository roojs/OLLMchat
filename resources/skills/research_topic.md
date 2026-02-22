---
name: research_topic
description: Use when you need to gather external information from the web (algorithms, libraries, best practices, troubleshooting) relevant to a coding task.
---

## Research topic skill

Use this skill when you need to gather external information from the web, such as finding algorithms, libraries, best practices, or troubleshooting steps relevant to a coding task.

### Description

Performs web research on a given topic to gather relevant information (algorithms, best practices, libraries, troubleshooting tips).

### Input

- **topic** (string): The subject to research (e.g. "fast factorial algorithm Python").

### Output

A summary of findings with key points and references (URLs). The summary should be concise and actionable.

### Instructions

1. Use the `web_search` tool with the provided topic as the query. If initial results are too broad or irrelevant, refine the query (e.g. add "programming", "Python", or "best practice").
2. Review the search results (titles, snippets, URLs). Select the most authoritative and relevant sources (e.g. official documentation, reputable blogs, Stack Overflow).
3. For each selected source, extract key information relevant to the topic. Focus on practical details that could be used in coding.
4. Compile the findings into a bullet-point summary. Include direct links to sources for reference.
5. Return the summary as a string. If no useful information is found, return a message indicating that.

### Example

**Input:** `topic = "async file I/O in Python"`

**Output:**

- Python's asyncio module provides async file I/O via aiofiles library (https://github.com/Tinche/aiofiles)
- Official asyncio docs: https://docs.python.org/3/library/asyncio.html
- Example: `async with aiofiles.open('file.txt') as f: contents = await f.read()`
- For small files, consider using threads with `loop.run_in_executor` to avoid blocking.
