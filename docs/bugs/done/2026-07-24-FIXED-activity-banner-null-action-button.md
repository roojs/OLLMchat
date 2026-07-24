# FIXED — ActivityBanner NULL action_button on construct

**Status:** ✅ FIXED — user verified 2026-07-24

**Started:** 2026-07-24

## Problem

🔷 App aborted at startup constructing `ActivityBanner` (`invalid (NULL) pointer instance` on `action_button.clicked.connect` in `construct`).

## Root cause

✔️ Vala/GObject: `construct` runs during `Object(...)`, before the public ctor body creates `action_button`.

## Fix applied

✔️ Wire `action_button.clicked` (and `notification.connect`) in the public constructor **after** the button exists — `ollmapp/ActivityBanner.vala`.

✅ User verified window opens.
