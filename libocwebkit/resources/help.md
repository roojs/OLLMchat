BROWSER TOOL
---
General-purpose web browser for THIS chat session. Search the web, open pages,
fill forms, follow links via press-refs from the page dump, download files.

NOT a one-shot HTTP API. Prefer the accessibility dump + press/fill over
shell/curl browsing.

MUST — HELP WHEN MISSING
  If this overview is NOT already in your current context (including after a
  conversation summary), call {"action": "help"} first.
  Before using an action whose topic page is not in context, call
  {"action": "help", "topic": "<action>"} (e.g. topic "press", "search").
  A vague recollection is not enough.

ACTIONS (call help with topic for details)
  help      — this index, or topic page when "topic" is set
  fetch     — open a URL
  search    — Google search (v1)
  press     — activate a press-ref; optional fill object on the same call
  download  — download a URL through this browser session
  whereami  — where am I? current page (no navigation)

DEFAULT PAGE DUMP (format "a11y")
  # Page → URL / Title
  ## Content — structured text; pressables as [label](^press:N)
  ## References — (^press:N): role, label; links as [text](url)

  Prefer press on a ref from the last dump over fetch with a hand-copied URL
  when the control is already listed. fill is an ARGUMENT on press, never an
  action. For format "html" / "markdown", call {"action": "help", "topic": "format"}.

TYPICAL FLOW
  help → search or fetch → read Content + References →
  press (+ fill) → read dump → repeat → download if needed

OTHER TOOLS
  google_search / web_fetch may still be registered. Prefer this tool for
  multi-step browsing and press/fill. Do not use them to replace press/fill
  on this tool’s dumps.
