# Rename Live.Handle to Live.Interface and add rpc_ctor_

**Status:** ⏳ open

**Started:** 2026-09-24

**Process:** `docs/bug-fix-process.md`

**Related:**

- ℹ️ gnome-shell-rpc `docs/bugs/2026-09-24-barrier-construct-before-lease.md` — `new Meta.Barrier({...})` runs property construct setters before the class `construct` block, while `rpc_lid` is still 0
- ℹ️ `libocrpc/Live/Handle.vala` — the interface today

---

## Problem

🔷 The interface is `OLLMrpc.Live.Handle`. The word `Handle` goes. The name is `OLLMrpc.Live.Interface`.

🔷 Construct-property helpers belong on that interface, not in gnome-shell-rpc. Every leased stub already implements it.

🔷 Those methods are prefixed `rpc_ctor_`.

🚫 Leaving the type named `Handle`.

🚫 An `IHandle` prefix.

🚫 A second interface in gnome-shell-rpc for this stash. `src/gi-stub/Stub.vala` is the draft to delete once this lands.

---

## Evidence

ℹ️ Current declaration:

```vala
namespace OLLMrpc.Live
{
	public interface Handle : GLib.Object
	{
		public abstract uint64 rpc_lid { get; set construct; }
	}
}
```

ℹ️ `Bin.Stream.parse_object` builds a leased proxy with `Object.new(type, "rpc-lid", id)`. Construct properties are applied before the class `construct` block. `rpc_lid != 0` means the server already has the object.

ℹ️ A local `new Meta.Barrier({ backend, x1, ... })` starts with `rpc_lid == 0`. GObject runs each property `construct` setter first. Those values have to be kept on the instance until the class `construct` block sends one `.new`.

---

## Proposed fix

**Where:** `libocrpc/Live/Handle.vala` renamed to `libocrpc/Live/Interface.vala`.

#### Remove

```vala
public interface Handle : GLib.Object
{
	public abstract uint64 rpc_lid { get; set construct; }
}
```

#### Replace with

```vala
public interface Interface : GLib.Object
{
	[GIR (visible = false)]
	public abstract uint64 rpc_lid { get; set construct; }

	/**
	 * Copy one construct property onto this instance.
	 * Call from a property {@code construct} setter. Does not RPC.
	 */
	[GIR (visible = false)]
	public void rpc_ctor_stash(string name, GLib.Value value)
	{
		var bag = this.get_data<CtorBag>("rpc-ctor");
		if (bag == null) {
			bag = new CtorBag();
			this.set_data("rpc-ctor", bag);
		}
		var copy = GLib.Value(value.type());
		value.copy(ref copy);
		bag.names.add(name);
		bag.props.add(copy);
	}

	/**
	 * Drop the construct stash. Safe when nothing was stored.
	 */
	[GIR (visible = false)]
	public void rpc_ctor_clear()
	{
		this.set_data("rpc-ctor", null);
	}

	/**
	 * @param name GIR property name
	 * @return the stashed value, or null when this construction did not set it
	 */
	[GIR (visible = false)]
	public GLib.Value? rpc_ctor_get(string name)
	{
		var bag = this.get_data<CtorBag>("rpc-ctor");
		if (bag == null) {
			return null;
		}
		for (var i = 0; i < bag.names.size; i++) {
			if (bag.names.get(i) == name) {
				return bag.props.get(i);
			}
		}
		return null;
	}

	/**
	 * @return true when at least one construct property was stashed
	 */
	[GIR (visible = false)]
	public bool rpc_ctor_has()
	{
		var bag = this.get_data<CtorBag>("rpc-ctor");
		return bag != null && bag.names.size > 0;
	}

}
```

Private `CtorBag` is declared at the top of `libocrpc/Live/Interface.vala`, in the namespace, ahead of the interface.

🔷 `[GIR (visible = false)]` on `rpc_lid` and each `rpc_ctor_*` method. valac 0.56 writes `introspectable="0"` on that property, its get/set accessors, and those methods. The interface itself stays introspectable.

🔷 `CtorBag` is a private class at the top of the file.

🔷 Call sites in this library and in gnome-shell-rpc change from `OLLMrpc.Live.Handle` to `OLLMrpc.Live.Interface`. `rpc_lid` stays the property name.

🔷 gnome-shell-rpc deletes `src/gi-stub/Stub.vala` and generates `this.rpc_ctor_stash`, `this.rpc_ctor_get`, `this.rpc_ctor_has`, and `this.rpc_ctor_clear` on the stub.

🚫 Adding these methods on a gnome-shell-rpc interface that the stub GIRs would have to implement.

---

## Attempts

✔️ 2026-09-24 — `libocrpc/Live/Handle.vala` replaced by `libocrpc/Live/Interface.vala`. `CtorBag` is private at the top of that file. `[GIR (visible = false)]` is on `rpc_lid` and the four `rpc_ctor_*` methods. This library's call sites and `docs/bin-rpc-protocol.md` say `Live.Interface`. `ninja -C build libocrpc/libocrpc.so tests/test-rpc-gi` succeeded.

⏳ gnome-shell-rpc still says `OLLMrpc.Live.Handle`, and `src/gi-stub/Stub.vala` is still the draft stash.
