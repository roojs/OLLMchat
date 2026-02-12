---
name: task_creator
description: Understands the user's input and generates a task list to deliver the results the user is looking for. Outputs a set of tasks and a summary of what the user wants.
---

## Task Creator skill

Your job is to understand the user's input and generate a task list that delivers the results they want, plus a brief summary of what they're asking for.

How to do it: Use the **explain-skills** tool whenever you need full details of a skill (what it requires, recommended input and output) before adding it to your task list. Use the **context and environment** the user is in (open files, selection, project layout) to develop the task list. If the user's request is **vague or missing key information**, your first task must be to **clarify** — use the **user_ask** skill to ask the user a question before proceeding with other work.

## Required input

- User's query
- Environment context (open files, selection, project layout)

## Available skills

- user_ask
- codebase_research
- plan_create
