package org.roojs.ollmchat.androidpoc;

import android.content.Context;
import android.content.Intent;
import android.os.Build;

/**
 * Start/stop {@link StreamingForegroundService} while an LLM stream runs.
 * Called from JNI (same pattern as {@link PartialWakeLock}).
 */
public final class StreamingForeground {
	private StreamingForeground() {
	}

	public static void set(Context context, boolean enable) {
		if (context == null) {
			return;
		}
		Context app = context.getApplicationContext();
		Intent intent = new Intent(app, StreamingForegroundService.class);
		if (enable) {
			intent.setAction(StreamingForegroundService.ACTION_START);
			if (Build.VERSION.SDK_INT >= 26) {
				app.startForegroundService(intent);
			} else {
				app.startService(intent);
			}
			return;
		}
		intent.setAction(StreamingForegroundService.ACTION_STOP);
		try {
			app.startService(intent);
		} catch (IllegalStateException e) {
			app.stopService(new Intent(app, StreamingForegroundService.class));
		}
	}
}
