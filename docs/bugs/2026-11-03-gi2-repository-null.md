# Gi.repo stays NULL because the static construct never runs

**Status:** ⏳ root cause confirmed; fix proposed. 2026-11-03. HEAD `4720779f`.

## Problem

- 🔷 `Gi.register` and `Gi.vfunc_offset` call `gi_repository_*` with a NULL repository. GLib logs `GI_IS_REPOSITORY (repository)` failed. `vfunc_offset` then hits `GLib.error` and aborts.
- 🔷 Expected: `Gi.repo` is the object from `GI.Repository.dup_default()`, `Gi.repository()` returns it, and `require("Gio", "2.0")` resolves `Gio.Application`.
- 🔷 Actual: the field is still NULL when those static methods run.

Reproduction on the Ubuntu 26.04 guest (`alan@192.168.122.115`, Vala 0.56.18, `libgirepository-2.0` 2.88.0), against `build/libocrpc/libocrpc.so`:

- ℹ️ gnome-shell-rpc `tests/call-sync-repro/gi-class-init-gate.c`, built there with `-Docrpc_libdir` pointing at this build.
- ℹ️ `gi-class-init-gate-fail` calls `oll_mrpc_gi_register("Gio", "2.0")` and does not class-ref `Gi`.
- ℹ️ `gi-class-init-gate-fix` is the same call after `g_type_class_unref (g_type_class_ref (oll_mrpc_gi_get_type ()))`.

## Evidence

- ✔️ Guest `gsr-server` at 09:55:15, `~/.cache/gnome-shell-rpc/mutter-rpc.debug.log`: `gi_repository_require`, `gi_repository_get_n_infos`, and `gi_repository_find_by_name` each fail `GI_IS_REPOSITORY (repository)`, then `Gi2.vala:258: Gi.vfunc_offset: no object Clutter.Actor`. Core pid 37578, SIGABRT. Stack: `oll_mrpc_gi_vfunc_offset` ← `gsr_server_clutter_actor_vfunc_ids_register_vfunc_ids` ← `gsr_server_rpc_server_start`.
- ✔️ `ldd` of that `gsr-server` shows `libgirepository-2.0.so.0` and this `libocrpc.so`. It does not show `libgirepository-1.0`.
- ✔️ `/tmp/gi2-check` on that guest: `gi_repository_dup_default()` is non-NULL and `gi_repository_require(repo, "Gio", "2.0", ...)` succeeds outside `Gi`.
- ✔️ Generated `build/libocrpc/libocrpc.so.p/Gi2.c`: `gi_repository_dup_default()` is assigned to `oll_mrpc_gi_repository` only in `oll_mrpc_gi_class_init`. `oll_mrpc_gi_register` and `oll_mrpc_gi_vfunc_offset` do not call `oll_mrpc_gi_get_type` or `g_type_class_ref`.
- ✔️ `gi-class-init-gate-fail` prints those two `GI_IS_REPOSITORY` criticals and `gi-class-init-gate: miss`, exit 1.
- ✔️ `gi-class-init-gate-fix` prints `gi-class-init-gate: ok`, exit 0.
- ✔️ Same valac, any class. `/tmp/static-construct.vala` sets `n = 7` inside `static construct` and prints `static construct`. `main` calls the static `get_n()`. The program printed `0` and did not print `static construct`. Generated `foo_get_n` returns `foo_n`. `foo_n = 7` is only in `foo_class_init`.

## Root cause

- ✔️ Vala 0.56.18 puts a `static construct` in `class_init` and does not class-ref the type from a static method. `Gi.repository = GI.Repository.dup_default()` therefore runs only after something else instantiates `Gi` or class-refs it. `register` and `vfunc_offset` do neither, so the field stays NULL.
- 🚫 This is not the 1.0/2.0 `GIRepository` GType clash. That binary links 2.0 only. `docs/bugs/2026-11-03-girepository-2.md` is the port this build already uses.
- 🚫 A null check that skips the call hides the missing repository. The field has to be assigned on the path the static methods actually run.

## Proposed fix

- 💩 Drop the `static construct`. `repository` assigns `dup_default()` to `Gi.repo` on first use and returns that object. Call sites use `Gi.repository()` instead of the field.

### `libocrpc/Gi2.vala` — `Gi.repo`

**Why:** `register`, `in_typelib`, `vfunc_offset`, `vfunc_names`, and `dispatch` read the repository before any class-ref.

**Where:** The field and its static construct, then each call site in this file.

**Depends on:** nothing.

#### Remove

```vala
		/**
		 * Process repository. 2.0 holds the full reference from
		 * {@link GI.Repository.dup_default}.
		 */
		internal static GI.Repository repository;

		static construct
		{
			Gi.repository = GI.Repository.dup_default();
		}
```

#### Replace with

```vala
		/**
		 * Process repository. 2.0 holds the full reference from
		 * {@link GI.Repository.dup_default}. Null until
		 * {@link repository}. Vala 0.56 runs a static construct
		 * only from class_init, and the static methods do not
		 * class-ref this type.
		 */
		internal static GI.Repository? repo;

		/**
		 * Repository for this process, creating it on first use.
		 *
		 * @return the process {@link GI.Repository}
		 */
		internal static GI.Repository repository()
		{
			var repo = Gi.repo;
			if (repo != null) {
				return repo;
			}
			repo = GI.Repository.dup_default();
			Gi.repo = repo;
			return repo;
		}
```

#### Replace with

```vala
			Gi.repository().require(ns, version, 0);
			var n = Gi.repository().get_n_infos(ns);
```

```vala
				var info = Gi.repository().get_info(ns, i);
```

```vala
			return Gi.repository().find_by_gtype(gtype) != null;
```

```vala
			var info = Gi.repository().find_by_name(ns, class_name);
```

- 💩 Same `Gi.repository()` replacement at the `find_by_name` in `vfunc_names`, the `find_by_gtype` in `dispatch`, and the `find_by_name` in `dispatch`.

### `libocrpc/GiMock2.vala` — `dispatch`

**Why:** Same field. Mock dispatch before any `Gi` instance hits the same NULL.

**Where:** Both reads in `dispatch`.

**Depends on:** the `Gi2.vala` change.

#### Replace with

```vala
				var info = Gi.repository().find_by_gtype(
					Gi.types.get(object_name));
```

```vala
				var info = Gi.repository().find_by_name(
					object_name, method_name);
```

### `libocrpc/Live/namespace.vala` — `boxed_ok`

**Why:** The 2.0 branch reads the repository from a static method.

**Where:** The `GIREPOSITORY_2` branch.

**Depends on:** the `Gi2.vala` change.

#### Remove

```vala
		var gi = Gi.repository.find_by_gtype(gtype);
```

#### Replace with

```vala
		var gi = Gi.repository().find_by_gtype(gtype);
```

## Attempts / changelog

- ✔️ Read the guest server log and core 37578. Confirmed the abort is `g_error` in `oll_mrpc_gi_vfunc_offset` after the `GI_IS_REPOSITORY` criticals, and that `class_init` is the only writer of `oll_mrpc_gi_repository`.
- ✔️ Compiled `/tmp/static-construct.vala` with valac 0.56.18. Static method returned `0`. Static construct did not run.
- ✔️ Ran the gnome-shell-rpc class-init gate against this `libocrpc.so`. Fail exit 1. Class-ref first, exit 0.

## Next

- ⏳ 💩 Apply the fences above, rebuild `libocrpc` on the 26.04 guest, and rerun `gi-class-init-gate-fail`. It should print `gi-class-init-gate: ok` without the class-ref.
