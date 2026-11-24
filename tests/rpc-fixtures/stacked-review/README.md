# Stacked review RPC fixture

Tier A target: `file_history` + backups + `stacked-review.txt` on disk (three pending `modified` rows).

Planned: checked-in `files.sqlite` slice or export script from gtktest1 `test-file.txt`.

Until then, `test-rpc-stacked-review.sh` fails the **fixture** check if history did not persist (known gap: multi-session / backup).