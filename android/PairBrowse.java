package org.roojs.ollmchat.androidpoc;

import android.content.Context;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.os.Handler;
import android.os.Looper;

public final class PairBrowse {
	private static NsdManager manager;
	private static NsdManager.DiscoveryListener listener;
	private static volatile String found = "";

	private PairBrowse() {
	}

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
				found = resolved.getHost().getHostAddress()
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
