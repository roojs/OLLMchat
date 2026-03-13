<!--
  Task list parse test: real LLM output shape (## Original prompt, ## Goals / summary, ## Tasks).
  To see why ResultParser validation might fail, run the document renderer with --debug to print
  header_list and headings keys (slugs) to stderr:
    ./build/oc-markdown-doc-test --debug tests/markdown/task-parse-test.md 2>&1 | head -30
  Expected slugs: original-prompt, goals-summary, tasks, task-section-1, ...
-->

## Original prompt

Our GTK markdown render now supports ` ```{langage} {description}`

I want to change that to support optional CSS:

` ```{language}.{css} {description}`

It will add that CSS class name to the frame as a class.

## Goals / summary

The task is to modify the code block syntax parsing in `RenderSourceView.vala` to support an optional CSS class name (prefixed with a dot) before the description. The new format should be ` ```{language}.{css-class} {description}` where `.css-class` gets added as a CSS class to the code frame/header widget.

## Tasks

### Task section 1

- **Name** Research Current Parsing Logic
- **What is needed** Find and analyze the current language/description parsing logic in RenderSourceView.vala to understand how it extracts language and description from the info string.
- **Skill** analyze_code
- **References** [RenderSourceView.vala](/home/alan/gitlive/OLLMchat/libocmarkdowngtk/RenderSourceView.vala)
- **Expected output** Findings document explaining current parsing behavior

- **Name** Research CSS Class Application
- **What is needed** Locate how CSS classes are currently added to frame/header widgets and find existing usage patterns in the codebase.
- **Skill** analyze_codebase
- **References** [RenderSourceView.vala](/home/alan/gitlive/OLLMchat/libocmarkdowngtk/RenderSourceView.vala)
- **Expected output** Findings on CSS class application patterns

### Task section 2

- **Name** Analysis New Parsing Requirements
- **What is needed** Analyze research outputs to design the new parsing logic that extracts language, optional CSS class (starting with dot), and description from the info string.
- **Skill** analyze_code
- **References** [Research Current Parsing Logic Results](task://research-current-parsing-logic.md), [Research CSS Class Application Results](task://research-css-class-application.md)
- **Expected output** Analysis document detailing parsing requirements and proposed changes

### Task section 3

- **Name** Plan Implementation
- **What is needed** Create a concrete plan for implementing the new CSS class syntax support with code proposals for modifying the parsing logic.
- **Skill** plan_code
- **References** [Analysis New Parsing Requirements Results](task://analysis-new-parsing-requirements.md)
- **Expected output** Code proposal with file changes

### Task section 4

- **Name** Review Implementation Plan
- **What is needed** Review the implementation plan against coding standards to ensure proper API usage before making code changes.
- **Skill** plan_review
- **References** [Plan Implementation Results](task://plan-implementation.md)
- **Expected output** Reviewed plan ready for implementation

### Task section 5

- **Name** Implement CSS Class Support
- **What is needed** Apply the planned changes to implement parsing of optional CSS class in code block syntax and add the class name to the frame header widget.
- **Skill** implement_code
- **References** [Plan Implementation Results](task://plan-implementation.md), [RenderSourceView.vala](/home/alan/gitlive/OLLMchat/libocmarkdowngtk/RenderSourceView.vala)
- **Expected output** Updated file with CSS class support

- **Requires user approval**
