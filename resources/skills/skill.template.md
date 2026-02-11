## How to use skills

- Pick a skill from the **descriptions** listed below (name and description from each skill's YAML header).
- Available skills are listed in the current skill document. After that, a **Tasks** section is injected (see below). Then the current skill's full instructions follow.

### Tasks

List each task with:

- **Skill** — name of the skill you want to run.
- **Query** — what to ask or pass in. Add bullet points with any information that this skill might find useful.
- **Output** — what you expect (e.g. a document; the skill will add a short summary at the end).

You can add a task to **ask the user to review** (e.g. **Skill** Conductor or a review skill, **Query** "Please review the following before we proceed", **Output** user confirmation). This is normally **essential prior to making any changes** to content that is not a plan or Research.

To run skills **concurrently**, list multiple skills in one task. To run **sequentially**, use a heading for each step (e.g. **Task 1**, **Task 2**).

## Current skill

{current_skill}

---
<user_query>
{query}
</user_query>
