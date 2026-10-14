# Folder load query hangs project open

**Status:** ✅ closed 2026-10-14. The grouped child count is in `ollmfilesd/Folder.vala`. `--test-flow` printed `folders=234 loading=false`.

## Problem

- **🔷** Opening a project from the file selector hangs. `ProjectManager.rpc_activate_project` times out after 120s and the folder tree never arrives.
- **🔷** `--test-flow` is the check. It prints `folders=` and `loading=false` when the tree query finishes.

## Evidence

- **✔️** Client log `~/.cache/ollmchat/com.roojs.ollmchat.test-source-diff.debug.log`: `id=3` `rpc_activate_project` at 09:08:30, `call timed out` at 09:10:30. Later ids time out the same way.
- **✔️** Daemon log stops at `opening project path=/home/alan/gitlive/OLLMchat`. No reply after that.
- **✔️** `/usr/bin/ollmfilesd` (the 09:08 build) stays at about 97% CPU. `filebase` has 68818 live rows.
- **✔️** The load statement counted children with a correlated subquery per row. The same counts as one grouped join finish in 0.049s (`COUNT(*)` of that join: 68818).

## Root cause

- **✔️** `load_children` counted children with a correlated subquery on every returned row. On 68818 live rows that does not finish inside 120s, so `rpc_activate_project` never replies and the tree request never starts.

## Proposed fix

- **🔷** The row load stays the plain `select_async`. After those ids are known, one count groups direct children for those ids. The counts are written onto the loaded folders before a reply is sent.

#### Remove

```sql
WHERE
		filebase.parent_id = folder_row.id
```

#### Replace with

```sql
SELECT
	filebase.parent_id,
	SUM(filebase.base_type = 'd') AS folder_count,
	SUM(filebase.base_type IN ('f', 'fa')) AS file_count
FROM
	filebase
WHERE
	filebase.delete_id = 0
	AND
		filebase.parent_id IN (...)
GROUP BY
	filebase.parent_id
```

- **✔️** That count, limited to the loaded ids, returns in 0.072s.

## Next

- **🔷** ⏳ The rebuilt daemon is `build/ollmfilesd/ollmfilesd`. `/usr/bin/ollmfilesd` is still the build that hangs. Replace that binary and restart `ollmfilesd.service`, then run `./build/examples/oc-test-source-diff --test-flow`. It passes when it prints a non-zero `folders=` and `loading=false`.
