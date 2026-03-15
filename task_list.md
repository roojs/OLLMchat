## Original prompt

In the coder task flow we write the task list to a series of files:
 * task list
 * completed list
 * proposed list

I'd like to simplify this so that we output the task list file only which consists of:
 * prompt
 * goals
 * completed
 * proposed

And we output that at each task list create stage and each task list iteration stage.

## Goals / summary

This task list aims to simplify the coder task flow by consolidating the separate task list, completed list, and proposed list files into a single unified file. The consolidated file will contain all four sections (prompt, goals, completed, proposed) and be output at each task list creation and iteration stage.

## Tasks

### Task section 1

- **Name** Research Task List System
- **What is needed** Find where the task list, completed list, and proposed list files are created and written in the codebase
- **Skill** analyze_codebase
- **References** [README.md](README.md)
- **Expected output** Findings on file paths and where task list operations are implemented

- **Name** Research File Writing Logic
- **What is needed** Locate the specific functions or methods that write task list files and understand their structure
- **Skill** analyze_codebase
- **References** [libollmchat/](/home/alan/gitlive/OLLMchat/libollmchat), [docs/](/home/alan/gitlive/OLLMchat/docs)
- **Expected output** Findings on file writing functions and their parameters

- **Name** Review Current Task File Format
- **What is needed** Examine existing task list files to understand their current structure and format
- **Skill** analyze_docs
- **References** [docs/](/home/alan/gitlive/OLLMchat/docs)
- **Expected output** Summary of current file format

### Task section 2

- **Name** Analyze Current Format
- **What is needed** Analyze the research findings to understand what sections need to be combined and how they map to the new single-file format
- **Skill** analyze_code
- **References** [Research Task List System Results](task://research-task-list-system.md), [Research File Writing Logic Results](task://research-file-writing-logic.md)
- **Expected output** Analysis document with proposed format mapping

### Task section 3

- **Name** Plan Task List Consolidation
- **What is needed** Create a plan for modifying the code to write a single unified task list file with all four sections
- **Skill** plan_create
- **References** [Analyze Current Format Results](task://analyze-current-format.md)
- **Expected output** Plan document with objectives, steps, and references

- **Name** Plan Review
- **What is needed** Review the consolidation plan against coding standards and API usage
- **Skill** plan_review
- **References** [Plan Task List Consolidation Results](task://plan-task-list-consolidation.md)
- **Expected output** Approved plan or recommendations

### Task section 4

- **Name** Implement Task List File Consolidation
- **What is needed** Modify the code to output a single task list file containing prompt, goals, completed, and proposed sections at each creation and iteration stage
- **Skill** implement_code
- **References** [Plan Task List Consolidation Results](task://plan-task-list-consolidation.md), [CODING_STANDARDS.md](.cursor/rules/CODING_STANDARDS.md)
- **Expected output** Updated code with consolidated task list file writing
- **Requires user approval**