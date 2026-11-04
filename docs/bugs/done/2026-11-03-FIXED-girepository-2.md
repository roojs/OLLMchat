# libocrpc binds girepository 1.0 when 2.0 is the one GJS uses

**Status:** ✅ 2026-11-04. User confirmed fixed. `Gi2.vala` / `GiMock2.vala` are the 2.0 copies. Class names stay `Gi` / `GiMock`. `Live.boxed_ok` is the one `#if GIREPOSITORY_2`.

## Problem

- 🔷 On Ubuntu 26.04, GJS links `libgirepository-2.0`. `libocrpc` links `libgirepository-1.0`.
- 🔷 Both libraries register a GType named `GIRepository`. The second registration aborts the process.
- 🔷 `libocrpc` builds against 2.0 when that pkg-config module is present, and stays on 1.0 when it is not.
- 🔷 A 26.04 build installs `libgirepository-2.0-dev` and does not install `libgirepository1.0-dev`.
- 🔷 A 25.04 / 25.10 build keeps `libgirepository1.0-dev`. GJS 1.82 there still links `libgirepository-1.0`.
- 🚫 Do not link both in one binary. Do not call `g_irepository_*` and then create a `Gjs.Context`.

## Evidence

- ℹ️ Consumer log: gnome-shell-rpc `docs/bugs/2026-11-02-starting-gnome-shell-hang.md`. Guest Ubuntu 26.04.1, GJS 1.88, mutter 50.1.
- ✔️ `gsr-client` reaches `Application.vala` `disable-user-extensions`, then `cannot register existing type 'GIRepository'`.
- ✔️ Moving only the client require onto `gi_repository_*` still crashed. Stack: `g_irepository_find_by_name` in `libgirepository-1.0.so.1` ← `oll_mrpc_gi_vfunc_offset` ← `shell_global_bind_display`.
- ✔️ gnome-shell-rpc `tests/call-sync-repro/gi-repository-gate.c`:
  - 1.0 `g_irepository_require("Gio")` then `gjs_context_new` prints `gi-repository-gate: miss`.
  - 2.0 `gi_repository_require("Gio")` then `gjs_context_new`, with no 1.0 call, prints `gi-repository-gate: ok`.
  - Linking `libgirepository-1.0` and not calling it also printed ok.
- ✔️ This host (Ubuntu 25.04): `pkg-config girepository-2.0` is absent. `ldd /usr/bin/gjs` is `libgirepository-1.0.so.1`. GJS 1.82.1.
- ✔️ 26.04 guest: `pkg-config --modversion girepository-2.0` is 2.88.0. `nm -D libgirepository-2.0.so.0` exports `gi_repository_dup_default`, `gi_repository_get_type`, `gi_function_info_invoke`. It does not export `g_irepository_get_default` or `g_function_info_invoke`.
- ✔️ `G_DECLARE_FINAL_TYPE (GIRepository, gi_repository, GI, REPOSITORY, GObject)` — the GType name stays `GIRepository`.
- ✔️ `gi_repository_dup_default` is `GI_AVAILABLE_IN_2_86`. `g-ir-generate` of `GIRepository-3.0.typelib` marks that return `transfer-ownership="full"`.
- ✔️ `/usr/share/gir-1.0/GIRepository-2.0.gir` (package `gir1.2-girepository-2.0-dev`) still says `shared-library="libgirepository-1.0.so.1"` and `g_irepository_get_default`. The 2.0 library's typelib is `GIRepository-3.0.typelib` (`gir1.2-girepository-3.0`), `shared-library="libgirepository-2.0.so.0"`.
- ✔️ Vala 0.56.18 `vapigen` on that typelib:
  - `g-ir-generate` writes `<repository version="1.0">`. vapigen: `unsupported GIR version 1.0`.
  - Rewriting the version to `1.2` still fails: `<type name="any"/>` is parsed as `G.DataStreamNewlineType.ANY`.
- ℹ️ Those call sites use `Gi.repository()`. On 1.0 that returns `GI.Repository.get_default()`. On 2.0 it returns `Gi.repo`.
  - `libocrpc/Gi.vala` — `require`, `get_n_infos`, `get_info`, `find_by_gtype`, `find_by_name`
  - `libocrpc/GiMock.vala` — `find_by_gtype`, `find_by_name`
  - `libocrpc/Live/namespace.vala` — `find_by_gtype`
- ℹ️ `Gi.g_function_info_invoke` is `[CCode (cname = "g_function_info_invoke", cheader_filename = "girepository.h")]`. 2.0's symbol is `gi_function_info_invoke`. The header is `girepository/girepository.h`.
- ℹ️ Meson hardcodes `gobject-introspection-1.0` in `libocrpc/meson.build`, `tests/meson.build` (`test-rpc-gi`), and `docs/meson.build` (valadoc).
- ℹ️ Apt name in `.github/workflows/x-debian.yml`, `x-sqgipkg.yml`, `remote-only-build.yml`, `deploy-docs.yml`, `docs/BUILD.md`, `docs/creating-releases.md`: `libgirepository1.0-dev`.
- ✔️ Guest `192.168.122.115` (Ubuntu 26.04.1, Vala 0.56.18, GJS 1.88.0). Both `-dev` packages happen to be installed. Probes linked only `libgirepository-2.0.so.0` (`ldd`).
- ✔️ `g-ir-generate` of `GIRepository-3.0.typelib` plus the fixes below, then `vapigen --nostdpkg --pkg=gobject-2.0 --pkg=glib-2.0 --pkg=gmodule-2.0`, writes a vapi. Namespace `GI`. Header `girepository/girepository.h`.
- ✔️ Plain `vapigen` (no `--nostdpkg`) fails inside `Gio-2.0.gir`, not inside GIRepository. That was the earlier "vapigen cannot" result.
- ✔️ Probe, metadata vapi, `dup_default`, `require("GObject")`:
  - `Gio.Application` is `GI.ObjectInfo`.
  - `GLib.Value`, `Bytes`, `Error`, `Date`, `DateTime` are `GI.StructInfo`. There is no boxed class.
  - `Gio.ApplicationFlags` is `GI.FlagsInfo` and also `GI.EnumInfo` (`FlagsInfo` subclasses `EnumInfo`). `GLib.DateMonth` is `EnumInfo` only.
  - `GLib.idle_add` arg `function` is `GI.CallbackInfo`. `get_closure_index` → 2. `get_destroy_index` → 3.
  - `gi_function_info_invoke` on `GLib.strdup` returned the string. `sizeof(GI.Argument)` in the generated C is `sizeof(GIArgument)` and is 8, same as the C union.
  - `(GI.StructInfo)` cast works. `get_size()` as `size_t` is 24 for `GLib.Value`. `new uint8[sz]` compiles.
  - `for (var i = 0; i < fn.get_n_args(); i++)` and `new bool[fn.get_n_args()]` compile against `uint32 get_n_args()`.
- ✔️ `gi_function_info_invoke` is not in the typelib. The vapi method `CallableInfo.invoke` is `gi_callable_info_invoke` and takes a function pointer. Different call.
- ✔️ `size_t n = struct_info.get_size()` does not compile while the vapi says `uint64`. Metadata `type="size_t"` matches the header and the existing locals.

## Root cause

- ✔️ `libocrpc` always takes `dependency('gobject-introspection-1.0')` on Unix. That loads `g_irepository_get_type`. GJS 1.88 then loads `gi_repository_get_type`. Same GType name.
- ✔️ 2.0 is not a renamed 1.0. `GIInfoType` and `BaseInfo.get_type()` are gone. Infos are separate GTypes. `get_default` is gone. `ArgInfo.get_closure()` (int, `-1` if none) is `get_closure_index(out uint)`. `TypeInfo.get_array_fixed_size()` (int, `-1` if none) is `bool` plus `out size_t`. A second `class Gi` that only wraps `dup_default` and `invoke` does not compile beside `Gi.vala`, and it leaves those call sites on the 1.0 API.

## Proposed fix

- 🔷 `libocrpc/Gi2.vala` is a copy of `libocrpc/Gi.vala`. The class stays `Gi`.
- 🔷 `libocrpc/GiMock2.vala` is a copy of `libocrpc/GiMock.vala`. The class stays `GiMock`.
- 🔷 Meson compiles one pair. 2.0 found: `Gi2.vala` and `GiMock2.vala`. Missing: `Gi.vala` and `GiMock.vala`. Same swap as `windows/Gi.vala`.
- 🚫 No `#if` in `Gi.vala` or `GiMock.vala`. The 1.0 and 2.0 copies are not edited into each other.
- 🔷 `Live/namespace.vala` stays one file. `boxed_ok` is the only `#if GIREPOSITORY_2`. Meson passes `--define=GIREPOSITORY_2` when `girepository-2.0` is found. No `namespace2.vala`.
- 💩 Commit `vapi/girepository-2.0.vapi` from the recipe below. Meson does not run `vapigen`. 25.04 has no `GIRepository-3.0.typelib`.
- 💩 Probe `girepository-2.0` first (`required: false`). Found: that dep and `--pkg=girepository-2.0`. Missing: today's `gobject-introspection-1.0`. A 2.0-only image never looks up the 1.0 pc file.
- ✔️ `Gi.repo` in `Gi2.vala` stores one `dup_default()`. Call sites use `Gi.repository()`, which fills `Gi.repo` on first use. `docs/bugs/done/2026-11-03-FIXED-gi2-repository-null.md`.
- 💩 The invoke extern in `Gi2.vala` uses cname `gi_function_info_invoke`. Do not call `CallableInfo.invoke`.
- 💩 Metadata keeps `ArgInfo.get_type()` and `FieldInfo.get_type()` as the `TypeInfo` fetch. `arg.get_type().get_tag()` stays. `BaseInfo.get_type()` returning `GI.InfoType` is what the copy changes.
- 🔷 `tests/meson.build` and `docs/meson.build` use the same dependency and the same `--pkg`. They do not add a second girepository.
- 🔷 Resolute image package: `libgirepository-2.0-dev`. Drop `libgirepository1.0-dev` on that image.
- 🚫 Do not install both `-dev` packages in one image. The meson probe cannot see which soname GJS uses. A 2.0-dev install on a GJS 1.0 image selects 2.0 and breaks that GJS the other way.
- 🚫 Do not vapigen `/usr/share/gir-1.0/GIRepository-2.0.gir`. That file is the 1.0 library.
- 🚫 Do not retarget the 1.0 vapi with `gi_*` cnames. `GI.InfoType` is not in the 2.0 headers.
- 🚫 Windows and Android stay on `windows/Gi.vala` and `windows/GiMock.vala`. No girepository there.
- 🚫 Do not compile `Gi.vala` and `Gi2.vala` in one build. Both declare `class Gi`.

### `vapi/girepository-2.0.vapi` — generate, then commit

**Why:** Vala 0.56 has no `girepository-2.0` binding. The typelib dump is not valid vapigen input until the steps below. The committed vapi is what 25.04 and 26.04 both compile.

**Where:** `vapi/girepository-2.0.vapi` and `vapi/girepository-2.0.deps`.

**Depends on:** a machine with `GIRepository-3.0.typelib` and Vala 0.56. Guest `192.168.122.115` produced a vapi that compiled the probes.

#### Add

`vapi/girepository-2.0.deps`:

```
gobject-2.0
```

Recipe, run once, commit the vapi. Not a meson step.

1. `g-ir-generate /usr/lib/x86_64-linux-gnu/girepository-1.0/GIRepository-3.0.typelib` to `GIRepository-3.0.gir`.
2. `<repository version="1.0"` → `version="1.2"`.
3. Each `<type name="any"/>` → `<type name="gpointer" c:type="gpointer"/>`. Those are padding fields. vapigen reads `any` as `GLib.DataStreamNewlineType.ANY`.
4. Insert `<c:include name="girepository/girepository.h"/>` before the namespace. Rename the namespace from `GIRepository` to `GI`. Leave `c:identifier` values alone.
5. Hoist each `<attribute name="c:identifier" value="…"/>` onto the parent as `c:identifier="…"`. vapigen does not read the element form. Without the hoist, `TypeTag.VOID` becomes `GI_VOID` instead of `GI_TYPE_TAG_VOID`.
6. Metadata file `GIRepository-3.0.metadata` next to the gir:

```
ArgInfo.get_type_info name="get_type"
FieldInfo.get_type_info name="get_type"
StructInfo.get_size type="size_t"
UnionInfo.get_size type="size_t"
StructInfo.get_alignment type="size_t"
UnionInfo.get_alignment type="size_t"
TypeInfo.get_array_fixed_size.out_size type="size_t"
FieldInfo.get_offset type="size_t"
```

7. `vapigen --nostdpkg --pkg=gio-2.0 --pkg=gobject-2.0 --pkg=glib-2.0 --pkg=gmodule-2.0 --metadatadir=<dir> --library=girepository-2.0 GIRepository-3.0.gir`. `--pkg=gio-2.0` stops vapigen reading `Gio-2.0.gir` (the GI gir includes Gio). `vapi/girepository-2.0.deps` stays `gobject-2.0`.

`libocrpc` already passes `--vapidir` of `vapi/`. No new vapidir on the library.

### `libocrpc/meson.build` — one girepository, one source pair

**Why:** The Unix build is the only one that links girepository. One dependency, one vapi, one of `Gi.vala` / `Gi2.vala`.

**Where:** above `if use_unix_sockets`, so `tests/` and `docs/` can read the variables. Inside the unix block, link that dep and pick `gi_src`. Probe 2.0 first. A 2.0-only image has no `gobject-introspection-1.0` pc file.

**Depends on:** `vapi/girepository-2.0.vapi`.

#### Remove

```meson
  ocrpc_deps += dependency('gobject-introspection-1.0')
  ocrpc_vapi_pkgs += '--pkg=gobject-introspection-1.0'
  ocrpc_vapi_gen_pkgs += [
    '--pkg', 'gobject-introspection-1.0',
  ]
```

#### Add

Above `if use_unix_sockets`:

```meson
girepository_2 = dependency('girepository-2.0', required: false)
if girepository_2.found()
  girepository_dep = girepository_2
  girepository_vapi = '--pkg=girepository-2.0'
else
  girepository_dep = dependency('gobject-introspection-1.0', required: use_unix_sockets)
  girepository_vapi = '--pkg=gobject-introspection-1.0'
endif
```

`required: use_unix_sockets` so Windows and Android configure does not demand the 1.0 pc file. Those builds do not link girepository.

Inside `if use_unix_sockets`:

```meson
  ocrpc_deps += girepository_dep
  ocrpc_vapi_pkgs += girepository_vapi
  ocrpc_vapi_gen_pkgs += ['--pkg', girepository_vapi.substring(6)]
  gi_src = files(['Gi.vala', 'GiMock.vala'])
  if girepository_2.found()
    ocrpc_vapi_pkgs += '--define=GIREPOSITORY_2'
    ocrpc_vapi_gen_pkgs += ['--define', 'GIREPOSITORY_2']
    gi_src = files(['Gi2.vala', 'GiMock2.vala'])
  endif
```

`live_src` stays `Live/namespace.vala`. The define selects the `boxed_ok` branch.

Windows and Android keep `windows/Gi.vala`.

### Copies

`Gi.vala` and `GiMock.vala` stay as they are.
`Gi2.vala` starts as a copy of `Gi.vala`. `public class Gi` stays.
`GiMock2.vala` starts as a copy of `GiMock.vala`. `public class GiMock` stays.
`Live/namespace.vala` is not copied. `boxed_ok` uses `#if GIREPOSITORY_2`.
The fences under the copy names are the only edits inside the copies.

### `libocrpc/Gi2.vala` — one repository, invoke cname

**Why:** `dup_default` returns a full reference. One field holds it. The invoke symbol and the `size_t` counts exist only on 2.0. The method name stays so the two call sites do not move.

**Where:** the existing extern, plus a static field and `static construct`.

**Depends on:** `vapi/girepository-2.0.vapi`. `Gi.vala` keeps `get_default()` and `g_function_info_invoke`.

#### Add

```vala
		internal static GI.Repository repository;
```

`internal` so `GiMock` and `Live.boxed_ok` can read it. Do not copy the field into a local.

```vala
		static construct
		{
			Gi.repository = GI.Repository.dup_default();
		}
```

#### Remove

```vala
		[CCode (cname = "g_function_info_invoke", cheader_filename = "girepository.h")]
		private static extern bool g_function_info_invoke(
			GI.FunctionInfo info,
			[CCode (array_length_cname = "n_in_args", array_length_pos = 2.5)] GI.Argument[] in_args,
			[CCode (array_length_cname = "n_out_args", array_length_pos = 3.5)] GI.Argument[] out_args,
			out GI.Argument return_value
		) throws GI.InvokeError;
```

#### Replace with

```vala
		[CCode (cname = "gi_function_info_invoke", cheader_filename = "girepository/girepository.h")]
		private static extern bool g_function_info_invoke(
			GI.FunctionInfo info,
			[CCode (array_length_cname = "n_in_args", array_length_pos = 2.5, array_length_type = "size_t")] GI.Argument[] in_args,
			[CCode (array_length_cname = "n_out_args", array_length_pos = 3.5, array_length_type = "size_t")] GI.Argument[] out_args,
			out GI.Argument return_value
		) throws GI.InvokeError;
```

The two call sites stay `g_function_info_invoke(...)`.

### `libocrpc/Gi2.vala` — `get_default` calls

**Why:** One field. These lines only change the receiver.

#### Remove

```vala
			GI.Repository.get_default().require(ns, version, 0);
			var n = GI.Repository.get_default().get_n_infos(ns);
```

```vala
				var info = GI.Repository.get_default().get_info(ns, i);
```

```vala
			return GI.Repository.get_default().find_by_gtype(gtype) != null;
```

```vala
			var info = GI.Repository.get_default().find_by_name(ns, class_name);
```

That `find_by_name` line is in both `vfunc_offset` and `vfunc_names`.

```vala
				var info = GI.Repository.get_default().find_by_gtype(
					types.get(object_name));
```

```vala
				var info = GI.Repository.get_default().find_by_name(
					object_name, method_name);
```

#### Replace with

```vala
			Gi.repository.require(ns, version, 0);
			var n = Gi.repository.get_n_infos(ns);
```

```vala
				var info = Gi.repository.get_info(ns, i);
```

```vala
			return Gi.repository.find_by_gtype(gtype) != null;
```

```vala
			var info = Gi.repository.find_by_name(ns, class_name);
```

```vala
				var info = Gi.repository.find_by_gtype(
					types.get(object_name));
```

```vala
				var info = Gi.repository.find_by_name(
					object_name, method_name);
```

### `libocrpc/Gi2.vala` — `register`

#### Remove

```vala
				if (info.get_type() != GI.InfoType.OBJECT
					&& info.get_type() != GI.InfoType.INTERFACE) {
					continue;
				}
```

#### Replace with

```vala
				if (!(info is GI.ObjectInfo) && !(info is GI.InterfaceInfo)) {
					continue;
				}
```

### `libocrpc/Gi2.vala` — `vfunc_offset`

`gi_field_info_get_offset` returns `size_t`. The cache map stores `int`.

#### Remove

```vala
			if (info == null || info.get_type() != GI.InfoType.OBJECT) {
				GLib.error("Gi.vfunc_offset: no object %s.%s", ns, class_name);
			}
```

```vala
			var offset = field.get_offset();
```

#### Replace with

```vala
			if (info == null || !(info is GI.ObjectInfo)) {
				GLib.error("Gi.vfunc_offset: no object %s.%s", ns, class_name);
			}
```

```vala
			var offset = (int) field.get_offset();
```

`gi_field_info_get_offset` returns `size_t`. The cache map stores `int`.

### `libocrpc/Gi2.vala` — `vfunc_names`

#### Remove

```vala
			if (info == null || info.get_type() != GI.InfoType.OBJECT) {
				GLib.error("Gi.vfunc_names: no object %s.%s", ns, class_name);
			}
```

#### Replace with

```vala
			if (info == null || !(info is GI.ObjectInfo)) {
				GLib.error("Gi.vfunc_names: no object %s.%s", ns, class_name);
			}
```

`for (var i = 0; i < object_info.get_n_vfuncs(); i++)` stays. The probe compiled that shape against `uint32`.

### `libocrpc/Gi2.vala` — `dispatch`

#### Remove

```vala
				if (info.get_type() == GI.InfoType.INTERFACE) {
```

```vala
				if (info == null || info.get_type() != GI.InfoType.FUNCTION) {
```

```vala
				if (arg.get_type().get_interface().get_type() != GI.InfoType.CALLBACK) {
					continue;
				}
				if (arg.get_closure() >= 0) {
					this.skip_wire[arg.get_closure()] = true;
				}
				if (arg.get_destroy() >= 0) {
					this.skip_wire[arg.get_destroy()] = true;
				}
```

#### Replace with

```vala
				if (info is GI.InterfaceInfo) {
```

```vala
				if (info == null || !(info is GI.FunctionInfo)) {
```

```vala
				if (!(arg.get_type().get_interface() is GI.CallbackInfo)) {
					continue;
				}
				uint32 closure_i = 0;
				if (arg.get_closure_index(out closure_i)) {
					this.skip_wire[closure_i] = true;
				}
				uint32 destroy_i = 0;
				if (arg.get_destroy_index(out destroy_i)) {
					this.skip_wire[destroy_i] = true;
				}
```

### `libocrpc/Gi2.vala` — `dispatch_function`

#### Remove

```vala
						var omit_iface = arg.get_type().get_interface();
						var omit_kind = omit_iface.get_type();
						if (omit_kind == GI.InfoType.STRUCT || omit_kind == GI.InfoType.BOXED) {
```

```vala
				var kind = arg.get_type().get_interface().get_type();
				size_t n = 0;
				if (kind == GI.InfoType.STRUCT || kind == GI.InfoType.BOXED) {
					var si = (GI.StructInfo) arg.get_type().get_interface();
					if (!si.is_gtype_struct()) {
						n = si.get_size();
					}
				} else if (kind == GI.InfoType.UNION) {
					n = ((GI.UnionInfo) arg.get_type().get_interface()).get_size();
				}
```

```vala
					var kind = ret_type.get_interface().get_type();
					if (kind != GI.InfoType.OBJECT && kind != GI.InfoType.INTERFACE) {
```

```vala
					var in_iface = arg.get_type().get_interface();
					var in_kind = in_iface.get_type();
					if (in_kind != GI.InfoType.STRUCT && in_kind != GI.InfoType.BOXED) {
```

#### Replace with

```vala
						var omit_iface = arg.get_type().get_interface();
						if (omit_iface is GI.StructInfo) {
```

```vala
				var face = arg.get_type().get_interface();
				size_t n = 0;
				if (face is GI.StructInfo) {
					var si = (GI.StructInfo) face;
					if (!si.is_gtype_struct()) {
						n = si.get_size();
					}
				} else if (face is GI.UnionInfo) {
					n = ((GI.UnionInfo) face).get_size();
				}
```

```vala
					var face = ret_type.get_interface();
					if (!(face is GI.ObjectInfo) && !(face is GI.InterfaceInfo)) {
```

```vala
					var in_iface = arg.get_type().get_interface();
					if (!(in_iface is GI.StructInfo)) {
```

### `libocrpc/Gi2.vala` — `convert_list`

#### Remove

```vala
			var kind = elem.get_interface().get_type();
			if (kind == GI.InfoType.STRUCT || kind == GI.InfoType.BOXED || kind == GI.InfoType.UNION) {
				size_t n = 0;
				if (kind == GI.InfoType.STRUCT || kind == GI.InfoType.BOXED) {
					var si = (GI.StructInfo) elem.get_interface();
					if (!si.is_gtype_struct()) {
						n = si.get_size();
					}
				}
				if (kind == GI.InfoType.UNION) {
					n = ((GI.UnionInfo) elem.get_interface()).get_size();
				}
```

```vala
			if (kind != GI.InfoType.OBJECT && kind != GI.InfoType.INTERFACE) {
```

#### Replace with

```vala
			var face = elem.get_interface();
			if (face is GI.StructInfo || face is GI.UnionInfo) {
				size_t n = 0;
				if (face is GI.StructInfo) {
					var si = (GI.StructInfo) face;
					if (!si.is_gtype_struct()) {
						n = si.get_size();
					}
				}
				if (face is GI.UnionInfo) {
					n = ((GI.UnionInfo) face).get_size();
				}
				if (n == 0) {
```

`if (n == 0)` is the existing line. The bytes-list body under it stays, then the existing `}` closes the `if` opened in both branches.

```vala
			if (!(face is GI.ObjectInfo) && !(face is GI.InterfaceInfo)) {
```

`face` is the 2.0 local from the hunk above. `kind` is the 1.0 local.

### `libocrpc/Gi2.vala` — `convert_interface`

#### Remove

```vala
			var kind = arg.get_type().get_interface().get_type();
			if (kind == GI.InfoType.CALLBACK) {
```

```vala
				var closure_i = arg.get_closure();
				if (closure_i >= 0) {
					this.in_args[this.in_slot[closure_i]].v_pointer = (void*) row;
				}
				var destroy_i = arg.get_destroy();
				if (destroy_i >= 0) {
					this.in_args[this.in_slot[destroy_i]].v_pointer = (void*) Live.Hook.drop;
				}
```

```vala
			if (kind == GI.InfoType.OBJECT || kind == GI.InfoType.INTERFACE) {
```

```vala
			if (kind == GI.InfoType.FLAGS) {
```

```vala
			if (kind == GI.InfoType.ENUM) {
```

```vala
			if (kind == GI.InfoType.STRUCT || kind == GI.InfoType.BOXED) {
```

That struct test occurs twice in this method (the `GLib.Value` pin, then the size walk).

```vala
			if (kind == GI.InfoType.STRUCT || kind == GI.InfoType.BOXED) {
				var si = (GI.StructInfo) arg.get_type().get_interface();
				if (!si.is_gtype_struct()) {
					n = si.get_size();
				}
			} else if (kind == GI.InfoType.UNION) {
				n = ((GI.UnionInfo) arg.get_type().get_interface()).get_size();
			}
```

#### Replace with

```vala
			var face = arg.get_type().get_interface();
			if (face is GI.CallbackInfo) {
```

```vala
				uint32 closure_i = 0;
				if (arg.get_closure_index(out closure_i)) {
					this.in_args[this.in_slot[closure_i]].v_pointer = (void*) row;
				}
				uint32 destroy_i = 0;
				if (arg.get_destroy_index(out destroy_i)) {
					this.in_args[this.in_slot[destroy_i]].v_pointer = (void*) Live.Hook.drop;
				}
```

```vala
			if (face is GI.ObjectInfo || face is GI.InterfaceInfo) {
```

```vala
			if (face is GI.FlagsInfo) {
```

```vala
			if (face is GI.EnumInfo && !(face is GI.FlagsInfo)) {
```

Both struct tests:

```vala
			if (face is GI.StructInfo) {
```

```vala
			if (face is GI.StructInfo) {
				var si = (GI.StructInfo) face;
				if (!si.is_gtype_struct()) {
					n = si.get_size();
				}
			} else if (face is GI.UnionInfo) {
				n = ((GI.UnionInfo) face).get_size();
			}
```

### `libocrpc/Gi2.vala` — `scalar`

#### Remove

```vala
					var kind = type.get_interface().get_type();
					if (kind == GI.InfoType.OBJECT || kind == GI.InfoType.INTERFACE) {
```

```vala
					if (kind == GI.InfoType.ENUM) {
```

```vala
					if (kind == GI.InfoType.FLAGS) {
```

```vala
					if (kind == GI.InfoType.STRUCT || kind == GI.InfoType.BOXED) {
```

That struct test occurs twice (the `GLib.Value` copy, then the size walk).

```vala
					if (kind == GI.InfoType.STRUCT || kind == GI.InfoType.BOXED) {
						var si = (GI.StructInfo) type.get_interface();
						if (!si.is_gtype_struct()) {
							n = si.get_size();
						}
					} else if (kind == GI.InfoType.UNION) {
						n = ((GI.UnionInfo) type.get_interface()).get_size();
					}
```

#### Replace with

```vala
					var face = type.get_interface();
					if (face is GI.ObjectInfo || face is GI.InterfaceInfo) {
```

Flags before enum. `FlagsInfo` is an `EnumInfo`.

```vala
					if (face is GI.FlagsInfo) {
```

```vala
					if (face is GI.EnumInfo && !(face is GI.FlagsInfo)) {
```

Both struct tests:

```vala
					if (face is GI.StructInfo) {
```

```vala
					if (face is GI.StructInfo) {
						var si = (GI.StructInfo) face;
						if (!si.is_gtype_struct()) {
							n = si.get_size();
						}
					} else if (face is GI.UnionInfo) {
						n = ((GI.UnionInfo) face).get_size();
					}
```

The current source tests enum before flags. The 2.0 branch tests flags first. Each branch returns, so either order is safe on 1.0. On 2.0, flags must not fall into the enum test.

### `libocrpc/Gi2.vala` — `scalar_array`

#### Remove

```vala
			var n_arr = type.get_array_fixed_size();
			if (n_arr < 0 && type.is_zero_terminated()
				&& (elem.get_tag() == GI.TypeTag.UTF8 || elem.get_tag() == GI.TypeTag.FILENAME)) {
```

```vala
			if (n_arr < 0) {
```

#### Replace with

```vala
			size_t n_arr = 0;
			var fixed = type.get_array_fixed_size(out n_arr);
			if (!fixed && type.is_zero_terminated()
				&& (elem.get_tag() == GI.TypeTag.UTF8 || elem.get_tag() == GI.TypeTag.FILENAME)) {
```

```vala
			if (!fixed) {
```

`new int[n_arr]` below stays. In this file `n_arr` is `size_t`.

### `libocrpc/Gi2.vala` — `scalar_list` and `scalar_hash`

#### Remove

```vala
			var kind = elem.get_interface().get_type();
			if (kind != GI.InfoType.OBJECT && kind != GI.InfoType.INTERFACE) {
```

```vala
			var kind = val_type.get_interface().get_type();
			if (kind != GI.InfoType.OBJECT && kind != GI.InfoType.INTERFACE) {
```

#### Replace with

```vala
			var face = elem.get_interface();
			if (!(face is GI.ObjectInfo) && !(face is GI.InterfaceInfo)) {
```

```vala
			var face = val_type.get_interface();
			if (!(face is GI.ObjectInfo) && !(face is GI.InterfaceInfo)) {
```

### `libocrpc/GiMock2.vala` — `dispatch`

#### Remove

```vala
				var info = GI.Repository.get_default().find_by_gtype(
					Gi.types.get(object_name));
				if (info.get_type() == GI.InfoType.INTERFACE) {
```

```vala
				var info = GI.Repository.get_default().find_by_name(
					object_name, method_name);
				if (info == null || info.get_type() != GI.InfoType.FUNCTION) {
```

```vala
				if (arg.get_type().get_interface().get_type() != GI.InfoType.CALLBACK) {
					continue;
				}
				if (arg.get_closure() >= 0) {
					this.skip_wire[arg.get_closure()] = true;
				}
				if (arg.get_destroy() >= 0) {
					this.skip_wire[arg.get_destroy()] = true;
				}
```

#### Replace with

```vala
				var info = Gi.repository.find_by_gtype(
					Gi.types.get(object_name));
				if (info is GI.InterfaceInfo) {
```

```vala
				var info = Gi.repository.find_by_name(
					object_name, method_name);
				if (info == null || !(info is GI.FunctionInfo)) {
```

```vala
				if (!(arg.get_type().get_interface() is GI.CallbackInfo)) {
					continue;
				}
				uint32 closure_i = 0;
				if (arg.get_closure_index(out closure_i)) {
					this.skip_wire[closure_i] = true;
				}
				uint32 destroy_i = 0;
				if (arg.get_destroy_index(out destroy_i)) {
					this.skip_wire[destroy_i] = true;
				}
```

### `libocrpc/GiMock2.vala` — `mint_object_lease` and `mock_empty_list`

#### Remove

```vala
			var kind = type.get_interface().get_type();
			if (kind != GI.InfoType.OBJECT && kind != GI.InfoType.INTERFACE) {
```

```vala
					var kind = elem.get_interface().get_type();
					if (kind != GI.InfoType.OBJECT && kind != GI.InfoType.INTERFACE) {
```

#### Replace with

```vala
			var face = type.get_interface();
			if (!(face is GI.ObjectInfo) && !(face is GI.InterfaceInfo)) {
```

```vala
					var face = elem.get_interface();
					if (!(face is GI.ObjectInfo) && !(face is GI.InterfaceInfo)) {
```

### `libocrpc/GiMock2.vala` — `mock_empty_interface`

This is the one switch. The 2.0 branch is the same arms as `if`s. Flags before enum.

#### Remove

```vala
			var kind = type.get_interface().get_type();
			switch (kind) {
				case GI.InfoType.ENUM:
					val = GLib.Value(typeof(int));
					val.set_int(0);
					return true;

				case GI.InfoType.FLAGS:
					val = GLib.Value(typeof(uint));
					val.set_uint(0);
					return true;

				case GI.InfoType.OBJECT:
				case GI.InfoType.INTERFACE:
					GLib.Object? token = null;
					if (!this.mint_object_lease(type, out token)) {
						return false;
					}
					if (token != null) {
						this.request.connection.export(token);
						val = OLLMrpc.val("o", token);
					}
					return true;

				case GI.InfoType.STRUCT:
				case GI.InfoType.BOXED:
				case GI.InfoType.UNION:
					size_t n = 0;
					if (kind == GI.InfoType.STRUCT || kind == GI.InfoType.BOXED) {
						var si = (GI.StructInfo) type.get_interface();
						if (!si.is_gtype_struct()) {
							n = si.get_size();
						}
					}
					if (kind == GI.InfoType.UNION) {
						n = ((GI.UnionInfo) type.get_interface()).get_size();
					}
					if (n == 0) {
						this.request.connection.reply_error(
							this.request, (int) RpcErrorCode.INVALID_PARAMS);
						return false;
					}
					var copy = new uint8[n];
					val = GLib.Value(typeof(GLib.Bytes));
					val.set_boxed(new GLib.Bytes(copy));
					return true;

				default:
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return false;
			}
```

#### Replace with

```vala
			var face = type.get_interface();
			if (face is GI.FlagsInfo) {
				val = GLib.Value(typeof(uint));
				val.set_uint(0);
				return true;
			}
			if (face is GI.EnumInfo) {
				val = GLib.Value(typeof(int));
				val.set_int(0);
				return true;
			}
			if (face is GI.ObjectInfo || face is GI.InterfaceInfo) {
				GLib.Object? token = null;
				if (!this.mint_object_lease(type, out token)) {
					return false;
				}
				if (token != null) {
					this.request.connection.export(token);
					val = OLLMrpc.val("o", token);
				}
				return true;
			}
			if (face is GI.StructInfo || face is GI.UnionInfo) {
				size_t n = 0;
				if (face is GI.StructInfo) {
					var si = (GI.StructInfo) face;
					if (!si.is_gtype_struct()) {
						n = si.get_size();
					}
				}
				if (face is GI.UnionInfo) {
					n = ((GI.UnionInfo) face).get_size();
				}
				if (n == 0) {
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return false;
				}
				var copy = new uint8[n];
				val = GLib.Value(typeof(GLib.Bytes));
				val.set_boxed(new GLib.Bytes(copy));
				return true;
			}
			this.request.connection.reply_error(
				this.request, (int) RpcErrorCode.INVALID_PARAMS);
			return false;
```

### `libocrpc/GiMock2.vala` — `mock_empty_array`

#### Remove

```vala
			var n_arr = type.get_array_fixed_size();
			if (n_arr < 0 && type.is_zero_terminated()
				&& (elem.get_tag() == GI.TypeTag.UTF8
					|| elem.get_tag() == GI.TypeTag.FILENAME)) {
```

```vala
			if (n_arr < 0) {
```

#### Replace with

```vala
			size_t n_arr = 0;
			var fixed = type.get_array_fixed_size(out n_arr);
			if (!fixed && type.is_zero_terminated()
				&& (elem.get_tag() == GI.TypeTag.UTF8
					|| elem.get_tag() == GI.TypeTag.FILENAME)) {
```

```vala
			if (!fixed) {
```

### `libocrpc/Live/namespace.vala` — `boxed_ok`

**Why:** This file is only `boxed_ok`. One `#if GIREPOSITORY_2` keeps the field walk. No second file.

The lookup and the two type tests are the split. The field walk under each test stays.

```vala
#if GIREPOSITORY_2
		var gi = Gi.repository.find_by_gtype(gtype);
#else
		var gi = GI.Repository.get_default().find_by_gtype(gtype);
#endif
```

```vala
#if GIREPOSITORY_2
		if (gi is GI.StructInfo) {
#else
		if (gi.get_type() == GI.InfoType.STRUCT || gi.get_type() == GI.InfoType.BOXED) {
#endif
```

```vala
#if GIREPOSITORY_2
		if (gi is GI.UnionInfo) {
#else
		if (gi.get_type() == GI.InfoType.UNION) {
#endif
```

`si.get_field(fi).get_type().get_tag()` stays. That `get_type()` is the field's `TypeInfo` on both libraries.

### `tests/meson.build` — `test-rpc-gi`

**Why:** An extra `gobject-introspection-1.0` link on a 2.0 `libocrpc` puts both sonames in the test binary. `gi-test.vala` does not name `GI`.

**Where:** `test_rpc_gi` dependencies and `vala_args`.

**Depends on:** `girepository_dep` from `libocrpc/meson.build`.

#### Remove

```meson
    dependency('gobject-introspection-1.0'),
```

and

```meson
    '--pkg=gobject-introspection-1.0',
```

#### Replace with

```meson
    girepository_dep,
```

No `--pkg` line. The test does not reference the vapi.

### `docs/meson.build` — valadoc pkg

**Why:** valadoc reads the same Gi sources the library compiled. On 2.0 that is `Gi2.vala` and `GiMock2.vala`, plus `Live/namespace.vala` with `--define=GIREPOSITORY_2`.

**Where:** `'--pkg=gobject-introspection-1.0'`.

**Depends on:** `girepository_vapi`.

#### Replace with

```meson
    girepository_vapi,
```

When `girepository_2.found()`, the `input:` list uses `Gi2.vala` and `GiMock2.vala` in place of `Gi.vala` and `GiMock.vala`. `Live/namespace.vala` stays, and the command adds `--define=GIREPOSITORY_2`. `--vapidir` of `vapi/` is already on that command.

## Attempts / changelog

- ✔️ Read `libocrpc/meson.build`, `Gi.vala`, `GiMock.vala`, `Live/namespace.vala`.
- ✔️ Guest `192.168.122.115`: headers, `nm`, GIR, typelib. First vapigen pass failed on repository version `1.0`, `<type name="any"/>`, and (without `--nostdpkg`) unrelated `Gio-2.0.gir` errors.
- ✔️ Same guest, second pass: gir fixes, `c:identifier` hoist, metadata, `vapigen --nostdpkg`. Probes compiled and ran against `libgirepository-2.0.so.0` only. Nothing in `libocrpc` was edited.
- ✔️ `#if` inside `Gi.vala` withdrawn. 2.0 is `Gi2.vala`, class `Gi`. Mock is `GiMock2.vala`, class `GiMock`.
- 🔷 `namespace2.vala` dropped. `boxed_ok` is `#if GIREPOSITORY_2` in `Live/namespace.vala`.
- ✔️ Applied the Gi2 / GiMock2 fences, `vapi/girepository-2.0.vapi`, and the meson probe. `Live/namespace2.vala` was not kept.
- ✔️ Guest `192.168.122.115`: `girepository-2.0` 2.88.0 selected. `libocrpc.so` links `libgirepository-2.0.so.0` and not `libgirepository-1.0`. `ninja` compiled `Gi2.vala`. `meson test test-rpc-gi` passed (0.02s).
- ✔️ This host: `girepository-2.0` absent, so the build stayed on `Gi.vala` and `gobject-introspection-1.0`. `libocrpc` compiled.
- ✅ 2026-11-04 — user confirmed this is fixed. Moved to `docs/bugs/done/`.

## Next

- ✅ 2026-11-04 — user confirmed this is fixed.
