# Task parse test 2: failed LLM output (JSON content shape)

This file replicates the content that failed to parse — the exact markdown that
would come from parsing the "content" field of the LLM response (with \n as real newlines).

To debug heading detection, run:
  ./build/oc-markdown-doc-test --debug tests/markdown/task-parse-test-2.md 2>&1 | head -40

Expected slugs: original-prompt, goals-summary, tasks, task-section-1, task-section-2, ...

## Original prompt

Our GTK markdown render now supports ` ```{language}<space>{description} ```. I want to change that to support optional CSS: ` ```{language}.{css}<space>{description}` `. It will add that CSS as a class name to the frame header.

## Goals / summary

Modify the `RenderSourceView.vala` code block parsing to support an optional CSS suffix (after a dot) in the language identifier, so users can specify custom CSS classes for the code frame header. The CSS class should be added to the frame's css_classes if provided in the syntax.

## Tasks

### Task section 1: Research current implementation

- **Name** Research 1
- **What is needed** Understand how the language and description are currently parsed from the info string, where the frame header gets its CSS classes applied, and how to extract the optional CSS suffix after a dot separator.
- **Skill** analyze_code
- **References** [`RenderSourceView.vala`](/home/alan/gitlive/OLLMchat/libocmarkdowngtk/RenderSourceView.vala)
- **Expected output** findings document explaining the current parsing logic and frame styling

### Task section 2: Analysis

- **Name** Analysis Current Structure
- **What is needed** Identify where to insert the CSS suffix parsing logic, how to validate/sanitize the CSS class name, and ensure backward compatibility with existing code blocks that don't have the `.css` suffix.
- **Skill** analyze_code
- **References** [`RenderSourceView.vala`](/home/alan/gitlive/OLLMchat/libocmarkdowngtk/RenderSourceView.vala), [Research 1 Results](task://research-1.md)
- **Expected output** plan section with specific code modifications needed

### Task section 3: Planning

- **Name** Plan 2
- **What is needed** Create a detailed plan for implementing the CSS suffix feature that maintains backward compatibility, validates class names safely, and tests the edge cases (empty css, multiple dots, invalid characters in css).
- **Skill** plan_create
- **References** [Analysis Current Structure Results](task://analysis-current-structure.md)
- **Expected output** detailed implementation plan with step-by-step code changes

### Task section 4: Implementation

- **Name** Implement CSS Suffix Support
- **What is needed** Apply the planned code changes to implement the `.css` suffix parsing, validate the class name before adding as a CSS class, and ensure backward compatibility.
- **Skill** implement_code
- **References** [Plan 2 Results](task://plan-2.md)
- **Expected output** updated RenderSourceView.vala with CSS suffix support
- **Requires user approval**

### Task section 5: Review

- **Name** Review Implementation
- **What is needed** Verify the implementation matches the requirements, check that existing code blocks without `.css` still work, and confirm the CSS class is correctly applied to the frame header.
- **Skill** plan_review
- **References** [Implement CSS Suffix Support Results](task://implement-css-suffix-support.md)
- **Expected output** review report confirming implementation correctness
