package org.roojs.ollmchat.androidpoc;

import android.content.Context;
import android.os.PowerManager;

/**
 * PARTIAL_WAKE_LOCK while an LLM stream is running — CPU/network may stay up
 * with the screen off or the app briefly backgrounded (OEM-dependent).
 */
public final class PartialWakeLock {
	private static PowerManager.WakeLock lock;

	private PartialWakeLock() {
	}

	public static void set(Context context, boolean enable) {
		if (context == null) {
			return;
		}
		PowerManager pm = (PowerManager) context.getApplicationContext()
			.getSystemService(Context.POWER_SERVICE);
		if (pm == null) {
			return;
		}
		synchronized (PartialWakeLock.class) {
			if (enable) {
				if (lock == null) {
					lock = pm.newWakeLock(
						PowerManager.PARTIAL_WAKE_LOCK,
						"ollmchat:stream");
					lock.setReferenceCounted(false);
				}
				if (!lock.isHeld()) {
					lock.acquire();
				}
				return;
			}
			if (lock != null && lock.isHeld()) {
				lock.release();
			}
		}
	}
}
