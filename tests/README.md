# Tests

## Prerequisites

- Build the project: `meson compile -C build`
- Ensure `tests/data/` is present (committed fixtures)

## Running tests

From the repo root:

- Edit ops: `./tests/test-edit-ops.sh`
- File ops: `./tests/test-file-ops.sh`
- Bubble tests: `./tests/test-bubble.sh`

### Build dir override

Each script accepts an optional build dir as the first argument:

`./tests/test-edit-ops.sh /path/to/build`

### Stop on first failure

Use the CLI flag or env var to exit on the first failure:

`./tests/test-edit-ops.sh --stop-on-failure`

`./tests/test-edit-ops.sh -x`

`STOP_ON_FAIL=1 ./tests/test-edit-ops.sh`

### Generate expected fixtures

Set `GENERATE_EXPECTED_MODE=1` to keep outputs for review:

`GENERATE_EXPECTED_MODE=1 ./tests/test-edit-ops.sh`

### Test artifacts

Tests write to `~/.cache/ollmchat/testing` and will clean up on success.
