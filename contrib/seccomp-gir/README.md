# libseccomp → GIR → Vala `.vapi` (spike)

Parent plan: [docs/plans/2.22.1.2-seccomp-manual-vapi-and-validation.md](../../docs/plans/2.22.1.2-seccomp-manual-vapi-and-validation.md).

## Canonical binding (object-oriented)

The checked-in Vala API lives at **`../../vapi/seccomp.vapi`**. It wraps `scmp_filter_ctx` as **`Seccomp.Filter`** (`new Seccomp.Filter (default_action)`), maps **`seccomp_release`** to **`free_function`**, and exposes ctx-first libseccomp calls as **instance methods** (`export_bpf`, `rule_add_array`, …). **`Seccomp.Filter.merge`** is a **static** method on the class.

Do **not** overwrite `../../vapi/seccomp.vapi` from vapigen; use the raw output below only as a reference when syncing new symbols.

## Prerequisites

- **`libseccomp`** development package (Debian/Ubuntu: `libseccomp-dev`).
- **`gobject-introspection`** (`g-ir-scanner`, `vapigen`; Debian: `libgirepository1.0-dev` / `gir1.2-*` toolchain).

## Regenerate (flat reference only)

From this directory:

```bash
./regenerate.sh
```

Produces **`Seccomp-${VER}.gir`** and **`seccomp-vapigen-raw.vapi`** (library name `seccomp-vapigen-raw` so it does not clobber the real **`seccomp`** package name). Manually port any new symbols into **`../../vapi/seccomp.vapi`**.

### Manual commands

```bash
VER=2.5   # adjust if your scanner namespace version differs from installed headers

g-ir-scanner --header-only \
  --namespace=Seccomp \
  --nsversion="${VER}" \
  --library=seccomp \
  --external-library \
  --pkg=libseccomp \
  --accept-unprefixed \
  /usr/include/seccomp.h \
  -o "Seccomp-${VER}.gir"

vapigen --library seccomp-vapigen-raw -d . "Seccomp-${VER}.gir"

sed -i 's/Seccomp-'"${VER}"'.h/seccomp.h/g' seccomp-vapigen-raw.vapi
```

## Smoke test (OO `vapi/seccomp.vapi`)

From this directory:

```bash
valac --vapidir=../../vapi --pkg seccomp --Xcc=-lseccomp test-minimal.vala -o test-minimal
./test-minimal
```

## Caveats

- **`--header-only`** does not evaluate every `#define`; some constants in the GIR may be wrong — compare when porting to the hand vapi.
- **`ArgCmp.op`** remains **`void*`** until a proper enum binding is added.
- Variadic **`seccomp_rule_add`** is only available via **`rule_add_array`** / C helpers.
