# Approved phone row is titled ollmchat

**Status:** ✅ 2026-10-31. The connections row titles this phone `Android SM-S9380 Samsung Galaxy S25 Ultra`.

## Problem

- 🔷 The desktop connections list titles this phone `ollmchat`. That is the app, not the handset.
- 🔷 Expected: registration stores the Android phone name, and that string is the row title.
- 🔷 This was already the requester goal. It was not delivered.

## Evidence

- ✔️ `ApprovedClientRow` sets the expander title from `client.requester`. `ollmapp/SettingsDialog/ApprovedClientRow.vala`.
- ✔️ The phone sends that field as the literal `ollmchat` on `ClientCert.request_registration`. `libollmchat/Settings/FilesdClient.vala`, the `args("sss", pin, csr, "ollmchat")` call.
- ✔️ [`RPC-8.2.8.1`](../../plans/done/RPC-8.2.8.1-DONE-filesd-desktop-connections-ui.md) says the requester is a device string. The example is Android `Build.MODEL`, a Samsung model such as `SM-A110O`. The desktop only stores and shows it.
- ✔️ [`RPC-8.2.8.2`](../../plans/done/RPC-8.2.8.2-DONE-filesd-android-file-connection.md) then sent `PRETTY_NAME` and wrote “no `Build.MODEL`”.
- ✔️ [`RPC-1.11.2`](../../plans/RPC-1.11.2-android-discovery-and-pair-cli.md) keeps the requester as `ollmchat`, the same string hello sends.
- ℹ️ This handset’s `adb devices -l` model is `SM_S9380`. Nothing in the tree reads `Build.MODEL` or the Android device-name setting.
- ✔️ 2026-10-31, `adb-R5CY134DA0W`: `getprop ro.product.model` is `SM-S9380`. `settings get global device_name` is `Alan's S25 Ultra`. `Build.MODEL` is the `ro.product.model` property. The same read is already in `examples/oc-test-source-diff.vala` (`__system_property_get`, 92-byte buffer).
- 🚫 The hello name stays `ollmchat`. This bug is the registration string the connections list shows.

## Root cause

- ✔️ Pairing stores the constant `ollmchat` in `client_cert.requester`. The row title is that column. The phone-name read from [`8.2.8.1`](../../plans/done/RPC-8.2.8.1-DONE-filesd-desktop-connections-ui.md) was never added.

## Proposed fix

- 🔷 The phone build of `try_connection` sends `ro.product.model` as the `request_registration` requester. On this handset that string is `SM-S9380`. The desktop already uses that column as the expander title.
- ℹ️ The Settings device name on this handset is `Alan's S25 Ultra`. [`8.2.8.1`](../../plans/done/RPC-8.2.8.1-DONE-filesd-desktop-connections-ui.md) names `Build.MODEL` as the requester, so this proposal sends the model.
- 🚫 Hello stays `ollmchat`.
- 🚫 The desktop does not rewrite a stored row. Registration inserts a new fingerprint. The current `ollmchat` row stays until it is removed and this phone pairs again.
- 🚫 An empty property is stored empty. The row then titles `Client N`. Do not substitute `ollmchat`.

### 1. `libollmchat/Settings/FilesdClient.vala` — file scope: bionic property call

**Why:** The Android build needs `__system_property_get`. The Linux pair test compiles this file without `ANDROID` and keeps sending `ollmchat`.

**Where:** After the copyright block, before `namespace OLLMchat.Settings`.

**Depends on:** none.

#### Add — declare the bionic call for the Android build

After the copyright block, before `namespace OLLMchat.Settings`.

```vala
#if ANDROID
[CCode (cheader_filename = "sys/system_properties.h")]
extern int __system_property_get(string name, [CCode (array_length = false)] uint8[] value);
#endif
```

### 2. `libollmchat/Settings/FilesdClient.vala` — `try_connection`: registration requester

**Why:** The third `request_registration` argument is the literal `ollmchat`. The phone build reads `ro.product.model` into that argument. The buffer length 92 is `PROP_VALUE_MAX`, the same size as `examples/oc-test-source-diff.vala`.

**Where:** The `ClientCert.request_registration` write in the `!has_credentials` branch of `try_connection`.

**Depends on:** §1.

#### Remove

```vala
				try {
					bin.write(new OLLMrpc.Request() {
						method = "ClientCert.request_registration",
						args = OLLMrpc.args("sss", pin, csr, "ollmchat")
					});
```

#### Replace with

```vala
				try {
#if ANDROID
					var model = new uint8[92];
					__system_property_get("ro.product.model", model);
#endif
					bin.write(new OLLMrpc.Request() {
						method = "ClientCert.request_registration",
						args = OLLMrpc.args("sss", pin, csr,
#if ANDROID
							(string) model
#else
							"ollmchat"
#endif
						)
					});
```

## Attempts / changelog

- ✔️ 2026-10-31: applied both fences in `libollmchat/Settings/FilesdClient.vala`. Host `ninja -C build libollmchat/libollmchat.so.p/Settings/FilesdClient.c` succeeded. The Android build compiled `__system_property_get("ro.product.model", …)` into that file and wrote `app-arm64-v8a-debug.apk`.
- ✔️ 09:36 — `adb install -r` on `adb-R5CY134DA0W`. Launched `ToplevelActivity`, pid 7516, `versionName=0.2.0`, `lastUpdateTime=2026-10-31 09:36:40`.

## Title reads as the model code

- 🔷 The row shows `SM-S9380`. Expected at least `Android SM-S9380`, and a product name at the end, in the shape `Samsung Note 24`.
- ✔️ 2026-10-31 10:29, `adb-R5CY134DA0W`: `ro.product.model` is `SM-S9380`, `ro.product.manufacturer` is `samsung`, `settings get global default_device_name` is `Galaxy S25 Ultra`. `device_name` is the renamed `Alan's S25 Ultra`. There is no `ro.product.marketname`.
- 🔷 The registration string is `Android SM-S9380 Samsung Galaxy S25 Ultra`. `Android` plus the model, then the manufacturer with its first letter uppercased, then `default_device_name`. This handset is a Galaxy S25 Ultra, so the product name is that, not Note 24.
- 🚫 Do not send `device_name`. That is the renamed handset (`Alan's S25 Ultra`).
- 🚫 Hello stays `ollmchat`. The stored row still changes only on the next registration.

### 3. `android/PairBrowse.java` — `bindLibrary`: build the row title

**Why:** `default_device_name` is a settings value. Startup already has the application context here.

**Where:** `bindLibrary`, after the library load and `nativeBind`.

**Depends on:** none.

#### Remove

```java
	public static void bindLibrary(Context context, String library) {
		System.loadLibrary(library);
		nativeBind(context.getApplicationContext());
	}

	private static native void nativeBind(Context context);
```

#### Replace with

```java
	public static void bindLibrary(Context context, String library) {
		Context app = context.getApplicationContext();
		String model = Build.MODEL;
		String brand = Build.MANUFACTURER;
		String product = Settings.Global.getString(
			app.getContentResolver(), "default_device_name");
		String label = "Android " + model;
		System.loadLibrary(library);
		nativeBind(app);
		if (brand != null && brand.length() > 0
			&& product != null && product.length() > 0
			&& !product.equals(model)) {
			label = label + " "
				+ brand.substring(0, 1).toUpperCase()
				+ brand.substring(1)
				+ " " + product;
		}
		nativePhoneLabel(label);
	}

	private static native void nativeBind(Context context);

	private static native void nativePhoneLabel(String label);
```

### 4. `libollmchat/Settings/FilesdClient.vala` — `try_connection`: send the caller’s string

**Why:** The phone passes the title. The Linux pair test passes `ollmchat`.

**Where:** `try_connection` signature and the `request_registration` argument. Drop the `ro.product.model` read.

**Depends on:** §3.

#### Remove

```vala
					args = OLLMrpc.args("sss", pin, csr,
#if ANDROID
							(string) model
#else
							"ollmchat"
#endif
						)
```

#### Replace with

```vala
					args = OLLMrpc.args("sss", pin, csr, requester)
```

## Attempts / changelog

- ✔️ 2026-10-31 10:39 — registration sends `Android` plus `Build.MODEL`, then the manufacturer and `default_device_name`. Host `ninja -C build tests/test-rpc-filesd-pair-flow` succeeded. Android APK rebuilt and `adb install -r` on `adb-R5CY134DA0W`. pid 24085, `lastUpdateTime=2026-10-31 10:39:05`.
- ✅ 2026-10-31 — the connections row shows `Android SM-S9380 Samsung Galaxy S25 Ultra`.

## Next

- 🚫 None. Fixed.
