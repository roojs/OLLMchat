---
name: analyze_code
description: Use when you need to find existing code in the codebase related to a concept, function, or feature so you can understand implementations and find places to modify.
---

## Analyze code skill

Use this skill when you need to find existing code in the codebase related to a concept, function, or feature. It helps you understand current implementations and locate places to modify.

### Description

Searches the codebase semantically to find existing code related to a concept, function, or feature.

### Input

- **query** (string): A description of what code to find (e.g. "function that calculates factorial", "database connection setup").

### Output

A list of code snippets with file paths and line numbers, formatted as a markdown list. If no relevant code is found, return an empty list.

### Instructions

1. Use the `semantic_search` tool with the given query. You may try different phrasings or synonyms to improve results.
2. For each result, record: file path, starting line number, a snippet of the code (e.g. the function or class definition), and relevance score if available.
3. Prioritize results by relevance. If many results, limit to the top 5–10 most relevant.
4. Format the output as:

   `file.py: lines 10-15`

   ```python
   def factorial(n):
       if n == 0: return 1
       return n * factorial(n-1)
   ```

5. Return the formatted list.

### Example

**Input:** `query = "function to calculate fibonacci"`

**Output:**

`math_utils.py: lines 20-25`

```python
def fibonacci(n):
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a
```
