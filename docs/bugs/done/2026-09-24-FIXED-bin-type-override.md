# Signal arguments need a bin type override

**Status:** ✅ FIXED — user archived. Registry and `pack_params` are in `libocrpc`. `test-rpc-subscribe` pass.

**Started:** 2026-09-24

**Process:** `docs/bug-fix-process.md`

**Related:**

- ℹ️ gnome-shell-rpc `docs/bugs/2026-09-24-signal-register-forward-override.md` — the crash, and the `Clutter.Event` subclass that will register here
- ℹ️ `libocrpc/Bin/StreamValue.vala` throws `unsupported bin value type` for a `GValue` that is not a bin scalar, a `Bin.Serializable`, or a registered boxed alias

---

## Problem

🔷 `OLLMrpc.Live.Subscription.emit` puts every signal argument on the notification as one bin value.

🔷 A type with no bin encoding (seen: `ClutterEvent`) resets the connection.

🔷 The argument must be written as several ordinary fields. Lookup is by the argument `GType`, not the signal name.

🚫 A `Clutter.Event` packer in this library. The subclass lives in gnome-shell-rpc and calls `OLLMrpc.Bin.TypeOverride.register`.

🚫 Registering pack and unpack delegates.

🚫 Generator tags. Signal-name checks. A "do not forward" flag.

---

## Existing flow

```text
Subscription.emit
  -> pack every param_values[i] as one bin value
  -> StreamValue rejects ClutterEvent
  -> connection reset
```

## Intended flow

🔷 One registered type becomes N wire fields on the way out, and N fields become one `GValue` on the way back.

🔷 An unregistered type stays one field.

---

## 1. Type registry

**Where:** `libocrpc/Bin/TypeOverride.vala`, namespace `OLLMrpc.Bin`. Same namespace as `Serializable` and `StreamValue`.

`Bin.register` and `Gi.register` stay lease aliases. They do not encode a Compact value.

#### Add

```vala
namespace OLLMrpc.Bin
{
	/**
	 * Pack and unpack one argument type on the signal wire.
	 *
	 * The registry is keyed by {@link override_type}. A missing type uses the
	 * bin value unchanged.
	 */
	public abstract class TypeOverride : GLib.Object
	{
		/**
		 * GType this override replaces on the wire.
		 *
		 * Lookup uses this, not the signal name.
		 */
		public abstract GLib.Type override_type { get; }

		/**
		 * Write src as wire fields.
		 *
		 * @param src the signal argument
		 * @return fields in wire order
		 */
		public abstract Gee.ArrayList<GLib.Value?> pack(GLib.Value src);

		/**
		 * Build the argument from wire fields.
		 *
		 * @param fields the notification arguments
		 * @param index first field for this argument
		 * @param consumed how many fields this argument used
		 * @return the argument value
		 */
		public abstract GLib.Value unpack(
			Gee.ArrayList<GLib.Value?> fields,
			int index,
			out int consumed
		);

		static Gee.HashMap<GLib.Type, TypeOverride>? by_type;

		/**
		 * Record one override under its argument type.
		 *
		 * @param over the override to record
		 */
		public static void register(TypeOverride over)
		{
			if (by_type == null) {
				by_type = new Gee.HashMap<GLib.Type, TypeOverride>();
			}
			by_type.set(over.override_type, over);
		}

		/**
		 * Find the override for a type.
		 *
		 * @param type the argument GType
		 * @return the override, or null when this type has none
		 */
		public static TypeOverride? lookup(GLib.Type type)
		{
			if (by_type == null || !by_type.has_key(type)) {
				return null;
			}
			return by_type.get(type);
		}

		/**
		 * Turn signal parameters into notification fields.
		 *
		 * Skips {@code param_values[0]}, the instance. An override replaces
		 * one parameter with the fields from {@link pack}.
		 *
		 * @param param_values instance then signal arguments
		 * @return fields in wire order
		 */
		public static Gee.ArrayList<GLib.Value?> pack_params(GLib.Value[] param_values)
		{
			var packed = new Gee.ArrayList<GLib.Value?>();
			for (var i = 1; i < param_values.length; i++) {
				var src = param_values[i];
				var helper = TypeOverride.lookup(src.type());
				if (helper == null) {
					packed.add(src);
					continue;
				}
				foreach (var field in helper.pack(src)) {
					packed.add(field);
				}
			}
			return packed;
		}

		/**
		 * Fill one GValue per signal parameter from notification fields.
		 *
		 * {@code dest[0]} is the instance and is left alone. An override
		 * consumes the field count from {@link unpack}. Any other parameter
		 * consumes one field.
		 *
		 * @param param_types signal parameter types, not including the instance
		 * @param fields the notification arguments
		 * @param dest instance at 0, then one slot per parameter, already inited
		 * @return how many fields were consumed
		 */
		public static int fill_params(
			GLib.Type[] param_types,
			Gee.ArrayList<GLib.Value?> fields,
			GLib.Value[] dest
		) {
			var wire = 0;
			for (var i = 0; i < param_types.length; i++) {
				var helper = TypeOverride.lookup(param_types[i]);
				if (helper != null) {
					var consumed = 0;
					helper.unpack(fields, wire, out consumed).transform(ref dest[i + 1]);
					wire += consumed;
					continue;
				}
				if (wire >= fields.size) {
					wire++;
					continue;
				}
				var src = fields.get(wire);
				if (!src.transform(ref dest[i + 1])
						&& src.holds(GLib.Type.OBJECT)
						&& param_types[i].is_a(GLib.Type.OBJECT)) {
					dest[i + 1].set_object(src.get_object());
				}
				wire++;
			}
			return wire;
		}
	}
}
```

**Where:** `libocrpc/meson.build`, `ocrpc_core_src`.

#### Replace with

```meson
  'Bin/StreamValue.vala',
  'Bin/Serializable.vala',
  'Bin/TypeOverride.vala',
```

---

## 2. Pack each signal argument

**Where:** `libocrpc/Live/Subscription.vala`, `Subscription.emit`.

#### Remove

```vala
			var packed = new Gee.ArrayList<GLib.Value?>();
			for (var i = 1; i < param_values.length; i++) {
				packed.add(param_values[i]);
			}
```

#### Replace with

```vala
			var packed = OLLMrpc.Bin.TypeOverride.pack_params(param_values);
```

---

## Conclusions

🔷 The walk of the signal-parameter list belongs next to the bin writer, because that writer sees one value and cannot turn one argument into several fields.

ℹ️ The caller of `fill_params` is gnome-shell-rpc `Signals.emit`. That call, the `Clutter.Event` subclass, and the empty `Clutter.Frame` fill stay in that tree.

---

## Attempts / changelog

- ✔️ 2026-09-24 — Opened from gnome-shell-rpc. Nested shell `SIGTRAP`: `unsupported bin value type 'ClutterEvent'` in `Subscription.emit`.
- ✔️ 2026-09-24 — Applied §1 and §2. No test registers an override or calls `fill_params`.
- ✅ 2026-09-24 — User archived. `Clutter.Event` registration stays in gnome-shell-rpc.
