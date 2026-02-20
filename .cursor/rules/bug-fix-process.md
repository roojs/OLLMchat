# Bug Fix Process

## Never hide bugs

**NEVER add protective or defensive checks (null checks, fallbacks, "just in case" guards) to mask failures.** They hide real bugs. We only discover issues like the documentation search null because we don't do that—failures surface and get fixed at the source.

## Required process

When fixing a bug, follow this order. Do not skip steps or apply code changes before approval.

### a) DEBUG first

- Reproduce the failure.
- Add **minimal, targeted** logging—only what’s needed to see the real values and control flow. Don’t splatter debug code everywhere; keep it small so we’re less likely to forget to remove it.
- Use **GLib.debug()** for debug output. Do not add method/class name in the message—file and line are already in the output.
- Prefer **readable output**: use strings when they’re more relevant than raw numbers (e.g. paths, IDs with context, “found”/“not found”); length alone is rarely enough. Output length is fine if it helps.
- Run and capture evidence. Do not guess.

### b) Understand the real issue

- From the evidence, identify the root cause (wrong data, wrong place, wrong assumption, missing step).
- Document it (e.g. in a plan or comment): what’s wrong and why it happens.

### c) Propose fix

- Propose a concrete fix that addresses the root cause, not the symptom.
- Describe the change and where it goes. No defensive workarounds.

### d) Get approval

- Present the diagnosis and proposed fix to the user (or reviewer).
- Wait for explicit approval before editing code.

### e) Only apply after approval

- Implement the approved fix only.
- Do not add extra “safety” checks or fallbacks unless they were part of the approved fix.

## Summary

1. **DEBUG first** → 2. **Understand real issue** → 3. **Propose fix** → 4. **Get approval** → 5. **Apply only after approval**

No protective checks that hide bugs.
