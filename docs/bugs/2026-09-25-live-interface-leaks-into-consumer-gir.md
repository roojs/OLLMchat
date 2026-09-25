# `Live.Interface` leaks an unresolved interface into consumer GIR

**Status:** ⏳ open — FAIL-backed outside the consumer product code

## Problem

- 🔷 A public GObject class may implement `OLLMrpc.Live.Interface` for RPC lease
  identity while exposing its own GIR/typelib.
- 🔷 Constructing that class through GJS must not crash GIRepository.
- ✔️ `gnome-shell-rpc/tests/call-sync-repro/live-interface-gir-gate` builds a
  standalone `Peer : GLib.Object, OLLMrpc.Live.Interface`, emits its GIR and
  typelib, and constructs it from GJS.
- ✔️ Current result is `SIGSEGV` with:

```text
g_irepository_find_by_name: assertion 'typelib != NULL' failed
```

## Evidence

- ✔️ The standalone generated GIR contains:

```xml
<implements name="OLLMrpc.LiveInterface"/>
```

- ✔️ It has no `<include name="OLLMrpc" .../>`; libocrpc does not install an
  OLLMrpc typelib.
- ✔️ gdb on the original `Shell.GLSLEffect` construction stops at:

```text
#0 g_interface_info_find_method
#1 g_object_info_find_method_using_interfaces
#2 libgjs.so.0
```

- ✔️ The same crash reproduces with the standalone `Peer`; Shell, Clutter,
  compositor RPC, and the application boot are absent.
- ℹ️ `Interface.rpc_lid` and all `rpc_ctor_*` methods already have
  `[GIR (visible = false)]`. The interface declaration itself does not.

## Root cause

- ✔️ `OLLMrpc.Live.Interface` is private RPC implementation metadata but its
  VAPI advertises a public GObject interface. Valac consequently writes that
  interface into every public consumer class's GIR.
- ✔️ GIRepository cannot resolve the advertised namespace because no OLLMrpc
  typelib exists. GJS follows the dangling interface while resolving object
  methods and segfaults before the consumer's GObject constructor runs.
- 🚫 This is not a constructor RPC deadlock. No constructor code is entered.
- 🚫 Do not remove the interface from consumer classes or special-case
  `Shell.GLSLEffect`.

## Proposed fix

- 🔷 The desired result is to omit the private OLLMrpc `<implements>` edge,
  not to make the interface non-introspectable.
- 🚫 Do not put `[GIR (visible = false)]` on the interface declaration.
  A standalone probe proves valac still emits `<implements>`, emits the
  interface as `introspectable="0"`, and GJS still segfaults while following
  it.
- ✔️ Valac has no annotation on an implementing class or one base-list entry
  that suppresses that `<implements>` element. It emits every interface in the
  class base list.
- 💩 Remove the OLLMrpc `<implements>` relation from generated consumer GIRs.
  The C class still implements the GType interface and Vala can still cast it;
  GI/GJS simply does not traverse private RPC metadata.
- ℹ️ gnome-shell-rpc already post-processes the generated Shell GIR through
  `scripts/gir-inject.xsl` before `g-ir-compiler`. That is the immediate place
  to omit `OLLMrpc.LiveInterface`; it is generated metadata handling, not a
  product constructor workaround.

#### Add

```xml
<xsl:template
  match="gi:implements[@name='OLLMrpc.LiveInterface']"/>
```

An upstream-supported way for consumers to omit this private implementation
edge is still preferable to each consumer independently naming it.

## Vala upstream

- ✔️ Checked Vala 0.56.19 (released 2026-03-30) and current upstream
  `codegen/valagirwriter.vala`. Neither supports suppressing one implemented
  interface.
- ✔️ Current `visit_class` still loops over every class base type and writes
  every `Interface` as `<implements>` without consulting `GIR.visible`.
- ✔️ Project issue and merge-request searches for `implements GIR`,
  `GIR visible`, `hide interface`, `introspectable interface`, and
  `girwriter interface` found no existing issue or MR for this behavior.
- ℹ️ Existing `GIR.visible` support is already available through
  `is_visibility(Symbol)`. The narrow Vala patch is to use it while writing
  class interface edges.

#### Remove

```vala
if (object_type.type_symbol is Interface) {
```

#### Replace with

```vala
if (object_type.type_symbol is Interface
		&& is_introspectable (object_type.type_symbol)) {
```

- 💩 Add a `tests/girwriter` case with a `[GIR (visible = false)]` interface
  implemented by a public class. Its expected GIR must contain the class and
  must not contain that interface in the class's `<implements>` list.
- 💩 Once that Vala behavior is available, annotate
  `OLLMrpc.Live.Interface` with `[GIR (visible = false)]`. This keeps the
  interface in the C ABI/VAPI while suppressing the private implementation
  edge in consumer GIR.

## Acceptance

- ⏳ `meson test -C build --print-errorlogs live-interface-gir-gate` prints
  `PASS live-interface-gir-gate`.
- ⏳ The fixture GIR contains no unresolved `OLLMrpc.LiveInterface`.
- ⏳ Rebuilding the consumer typelib allows direct `new Shell.GLSLEffect()` and
  the MessageView fade effect to reach `Helper-GLSLEffect.create`.

## Attempts / changelog

- ✔️ 2026-09-25: reduced full boot to direct GJS construction.
- ✔️ 2026-09-25: captured GIRepository backtrace.
- ✔️ 2026-09-25: added standalone GIR/typelib/GJS gate; current library fails
  by SIGSEGV.
- ✔️ 2026-09-25: tested `[GIR (visible = false)]` on the interface declaration.
  Valac retained `<implements>`, marked the interface non-introspectable, and
  GJS still SIGSEGVed.
- ✔️ 2026-09-25: tested the same interface with valid introspectable metadata
  in the typelib while keeping its property hidden. GJS constructed the class
  successfully.
- 🚫 No libocrpc code changed from the consumer tree.
