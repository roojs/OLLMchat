package org.roojs.ollmchat.androidpoc;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;

/**
 * Foreground service (type dataSync) while an LLM stream is running.
 * Promotes the process so libsoup SSE is less likely to be killed under Doze.
 */
public final class StreamingForegroundService extends Service {
	static final String ACTION_START = "org.roojs.ollmchat.androidpoc.STREAM_START";
	static final String ACTION_STOP = "org.roojs.ollmchat.androidpoc.STREAM_STOP";

	private static final String CHANNEL_ID = "ollmchat_streaming";
	private static final int NOTIF_ID = 4201;

	@Override
	public int onStartCommand(Intent intent, int flags, int startId) {
		if (intent != null && ACTION_STOP.equals(intent.getAction())) {
			stopForeground(STOP_FOREGROUND_REMOVE);
			stopSelf();
			return START_NOT_STICKY;
		}
		ensureChannel();
		Notification notification = buildNotification();
		if (Build.VERSION.SDK_INT >= 34) {
			startForeground(NOTIF_ID, notification,
				ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC);
		} else {
			startForeground(NOTIF_ID, notification);
		}
		return START_STICKY;
	}

	@Override
	public void onDestroy() {
		stopForeground(STOP_FOREGROUND_REMOVE);
		super.onDestroy();
	}

	@Override
	public IBinder onBind(Intent intent) {
		return null;
	}

	private void ensureChannel() {
		if (Build.VERSION.SDK_INT < 26) {
			return;
		}
		NotificationManager nm = getSystemService(NotificationManager.class);
		if (nm == null || nm.getNotificationChannel(CHANNEL_ID) != null) {
			return;
		}
		NotificationChannel channel = new NotificationChannel(
			CHANNEL_ID,
			"OLLMchat generating",
			NotificationManager.IMPORTANCE_LOW);
		channel.setDescription("Shown while a chat reply is streaming");
		nm.createNotificationChannel(channel);
	}

	private Notification buildNotification() {
		Intent launch = getPackageManager().getLaunchIntentForPackage(getPackageName());
		PendingIntent content = null;
		if (launch != null) {
			int piFlags = PendingIntent.FLAG_UPDATE_CURRENT;
			if (Build.VERSION.SDK_INT >= 23) {
				piFlags |= PendingIntent.FLAG_IMMUTABLE;
			}
			content = PendingIntent.getActivity(this, 0, launch, piFlags);
		}
		Notification.Builder builder;
		if (Build.VERSION.SDK_INT >= 26) {
			builder = new Notification.Builder(this, CHANNEL_ID);
		} else {
			builder = new Notification.Builder(this);
		}
		builder.setContentTitle("OLLMchat")
			.setContentText("Generating reply…")
			.setSmallIcon(android.R.drawable.stat_notify_sync)
			.setOngoing(true)
			.setOnlyAlertOnce(true);
		if (content != null) {
			builder.setContentIntent(content);
		}
		return builder.build();
	}
}
