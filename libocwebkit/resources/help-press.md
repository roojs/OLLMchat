BROWSER TOOL — action press (and argument fill)
---
Activate a press-ref from the LAST a11y dump for this chat.

Arguments:
  press   {integer}  Required. Press id from [label](^press:N) / References.
  fill    {object}   Optional. NOT an action. Only with action "press".
                     Map of press-ref id → text to type.
                     Example: {"1": "site:example.com release notes"}
                     Keys are unique (one text per ref).
  format  {string}   Optional. "a11y" (default), "html", or "markdown".

Order when fill is present: apply all fill entries, then press, then dump.

Examples:
  {"action": "press", "press": 3}
  {"action": "press", "press": 2,
   "fill": {"1": "site:example.com release notes"}}

Prefer press over fetch when the control or link is already in References.
fill is never a value of "action".
