<!--
  Nested thinking markdown (same path as ChatView thinking frame).

  ChatView (append_complete_assistant_message / streaming) feeds each chunk with
  process_new_chunk_direct → process_add_text_direct → thinking_frame.add_code_text(text)
  in one call per chunk (full string may contain newlines).

  oc-test-gtkmd match for restore-style single blob:
    build/examples/oc-test-gtkmd --thinking tests/markdown/repro-chatview-thinking-lines.md

  For chunk-by-chunk stress (random small pieces), use:
    build/examples/oc-test-gtkmd --thinking --stream 0 tests/markdown/repro-chatview-thinking-lines.md

  Body below mirrors failing traces: nested bullets, **bold**, backticks, "Shared references" line.
-->

Thinking Process:

1.  **Analyze the Request:**
    *   **Role:** Refiner.
    *   **Job:** Organize the task list into the `## Task` section format (concise nested list).
    *   **Constraints:**
        *   Output *only* the `## Task` section (markdown list).
        *   Follow `Balance shared vs examination` rules.
    *   **Goal:** Create a refined task structure.

2.  **Decide references:**
    *   **Task:** Flow analysis.
        *   I will use **Shared references** for the code links.
        *   Next fragment may continue on the following line in the real stream.
