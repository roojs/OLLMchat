package org.roojs.ollmchat.androidpoc;

import android.content.Context;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;

public final class PairBrowse {
	private static NsdManager manager;
	private static NsdManager.DiscoveryListener listener;
	private static volatile String found = "";

	private PairBrowse() {
	}

	public static void bind(Context context) {
		bindLibrary(context, "ollmchat-android-poc");
	}

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

	public static void start(Context context) {
		found = "";
		if (context == null) {
			found = "none";
			return;
		}
		new Handler(Looper.getMainLooper()).post(() -> browse(context));
	}

	private static void browse(Context context) {
		NsdManager nsd = (NsdManager) context.getApplicationContext()
			.getSystemService(Context.NSD_SERVICE);
		if (nsd == null) {
			found = "none";
			return;
		}
		manager = nsd;
		listener = new NsdManager.DiscoveryListener() {
			public void onDiscoveryStarted(String type) {
			}

			public void onDiscoveryStopped(String type) {
			}

			public void onStartDiscoveryFailed(String type, int error) {
				found = "none";
			}

			public void onStopDiscoveryFailed(String type, int error) {
			}

			public void onServiceLost(NsdServiceInfo info) {
			}

			public void onServiceFound(NsdServiceInfo info) {
				if (found != null && found.length() > 0 && !found.equals("none")) {
					return;
				}
				resolve(nsd, info);
			}
		};
		nsd.discoverServices("_rpc._tcp.", NsdManager.PROTOCOL_DNS_SD, listener);
		new Handler(Looper.getMainLooper()).postDelayed(() -> {
			if (found == null || found.length() == 0) {
				found = "none";
			}
			stop(context);
		}, 30000);
	}

	private static void resolve(NsdManager nsd, NsdServiceInfo info) {
		nsd.resolveService(info, new NsdManager.ResolveListener() {
			public void onResolveFailed(NsdServiceInfo failed, int error) {
			}

			public void onServiceResolved(NsdServiceInfo resolved) {
				if (resolved.getHost() == null) {
					return;
				}
				byte[] raw = resolved.getAttributes().get("id");
				if (raw == null || raw.length == 0) {
					return;
				}
				String id;
				try {
					id = new String(raw, "UTF-8");
				} catch (java.io.UnsupportedEncodingException e) {
					return;
				}
				found = id + "\n" + resolved.getHost().getHostAddress()
					+ ":" + resolved.getPort();
			}
		});
	}

	public static String poll() {
		return found == null ? "" : found;
	}

	public static void stop(Context context) {
		new Handler(Looper.getMainLooper()).post(() -> {
			if (manager != null && listener != null) {
				try {
					manager.stopServiceDiscovery(listener);
				} catch (IllegalArgumentException ignored) {
				}
				listener = null;
			}
		});
	}
}
