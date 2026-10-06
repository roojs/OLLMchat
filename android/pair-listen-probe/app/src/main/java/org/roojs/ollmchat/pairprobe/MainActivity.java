package org.roojs.ollmchat.pairprobe;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.pm.PackageManager;
import android.net.nsd.DiscoveryRequest;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.net.wifi.WifiManager;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.InputType;
import android.util.Log;
import android.view.ViewGroup;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

/**
 * Standalone check of the phone pairing listen.
 *
 * Browses _rpc._tcp the same way PairBrowse does. The screen stays on
 * Listening until some other host resolves. A PIN field appears then.
 */
public class MainActivity extends Activity {
	private static final String TAG = "pair-probe";
	private static final String SERVICE_TYPE = "_rpc._tcp.";
	private static final String OWN_NAME = "pair-probe-local";

	private final Handler handler = new Handler(Looper.getMainLooper());
	private TextView status;
	private EditText pin;
	private TextView logView;
	private final StringBuilder log = new StringBuilder();
	private NsdManager nsd;
	private NsdManager.DiscoveryListener discovery;
	private NsdManager.RegistrationListener registration;
	private WifiManager.MulticastLock multicast;
	private boolean foreign;
	private boolean heardOwn;

	@Override
	protected void onCreate(Bundle savedInstanceState) {
		super.onCreate(savedInstanceState);
		LinearLayout column = new LinearLayout(this);
		column.setOrientation(LinearLayout.VERTICAL);
		int pad = 48;
		column.setPadding(pad, pad, pad, pad);
		status = new TextView(this);
		status.setText("Listening");
		status.setTextSize(28);
		column.addView(status);
		pin = new EditText(this);
		pin.setHint("Six digits");
		pin.setInputType(InputType.TYPE_CLASS_NUMBER);
		pin.setVisibility(EditText.GONE);
		column.addView(pin);
		logView = new TextView(this);
		logView.setTextSize(14);
		ScrollView scroll = new ScrollView(this);
		scroll.addView(logView, new ViewGroup.LayoutParams(
			ViewGroup.LayoutParams.MATCH_PARENT,
			ViewGroup.LayoutParams.WRAP_CONTENT));
		column.addView(scroll, new LinearLayout.LayoutParams(
			ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));
		setContentView(column);

		if (checkSelfPermission(Manifest.permission.NEARBY_WIFI_DEVICES)
			!= PackageManager.PERMISSION_GRANTED) {
			requestPermissions(
				new String[] { Manifest.permission.NEARBY_WIFI_DEVICES }, 1);
		}
		nsd = (NsdManager) getSystemService(Context.NSD_SERVICE);
		note("browse via DiscoveryRequest");
		browse();
		handler.postDelayed(this::retryWithLock, 8000);
		handler.postDelayed(this::publishLocal, 16000);
		handler.postDelayed(this::giveUp, 30000);
	}

	@Override
	protected void onDestroy() {
		handler.removeCallbacksAndMessages(null);
		stopBrowse();
		if (nsd != null && registration != null) {
			try {
				nsd.unregisterService(registration);
			} catch (IllegalArgumentException ignored) {
			}
			registration = null;
		}
		if (multicast != null && multicast.isHeld()) {
			multicast.release();
		}
		super.onDestroy();
	}

	private void retryWithLock() {
		if (foreign) {
			return;
		}
		WifiManager wifi = (WifiManager) getSystemService(Context.WIFI_SERVICE);
		multicast = wifi.createMulticastLock("pair-probe");
		multicast.setReferenceCounted(false);
		multicast.acquire();
		note("no foreign service yet; multicast lock held, browse again");
		stopBrowse();
		browse();
	}

	private void publishLocal() {
		if (foreign || nsd == null) {
			return;
		}
		NsdServiceInfo info = new NsdServiceInfo();
		info.setServiceName(OWN_NAME);
		info.setServiceType(SERVICE_TYPE);
		info.setPort(9753);
		registration = new NsdManager.RegistrationListener() {
			public void onServiceRegistered(NsdServiceInfo registered) {
				note("registered " + registered.getServiceName());
			}

			public void onRegistrationFailed(NsdServiceInfo failed, int error) {
				note("register failed " + error);
			}

			public void onServiceUnregistered(NsdServiceInfo unregistered) {
			}

			public void onUnregistrationFailed(NsdServiceInfo failed, int error) {
			}
		};
		note("register local " + SERVICE_TYPE + " port 9753");
		nsd.registerService(info, NsdManager.PROTOCOL_DNS_SD, registration);
	}

	private void giveUp() {
		if (foreign) {
			return;
		}
		status.setText("No desktop found");
		note(heardOwn
			? "timeout; heard only the local registration"
			: "timeout; heard nothing");
	}

	private void browse() {
		if (nsd == null) {
			note("NsdManager missing");
			status.setText("No desktop found");
			return;
		}
		discovery = new NsdManager.DiscoveryListener() {
			public void onDiscoveryStarted(String type) {
				note("discovery started " + type);
			}

			public void onDiscoveryStopped(String type) {
				note("discovery stopped " + type);
			}

			public void onStartDiscoveryFailed(String type, int error) {
				note("discovery failed " + error);
			}

			public void onStopDiscoveryFailed(String type, int error) {
				note("stop failed " + error);
			}

			public void onServiceLost(NsdServiceInfo info) {
				note("lost " + info.getServiceName());
			}

			public void onServiceFound(NsdServiceInfo info) {
				note("found " + info.getServiceName()
					+ " port=" + info.getPort()
					+ " host=" + info.getHost()
					+ " hosts=" + info.getHostAddresses());
				if (OWN_NAME.equals(info.getServiceName())) {
					heardOwn = true;
					return;
				}
				if (info.getHostAddresses() != null
					&& !info.getHostAddresses().isEmpty()) {
					showHit(info);
					return;
				}
				resolve(info);
			}
		};
		DiscoveryRequest request = new DiscoveryRequest.Builder(SERVICE_TYPE).build();
		nsd.discoverServices(request, getMainExecutor(), discovery);
	}

	private void resolve(NsdServiceInfo info) {
		note("resolve " + info.getServiceName());
		nsd.registerServiceInfoCallback(info, getMainExecutor(),
			new NsdManager.ServiceInfoCallback() {
				public void onServiceInfoCallbackRegistrationFailed(int error) {
					note("info callback failed " + error);
				}

				public void onServiceInfoCallbackUnregistered() {
				}

				public void onServiceLost() {
					note("info lost " + info.getServiceName());
				}

				public void onServiceUpdated(NsdServiceInfo updated) {
					note("updated " + updated.getServiceName()
						+ " port=" + updated.getPort()
						+ " host=" + updated.getHost()
						+ " hosts=" + updated.getHostAddresses());
					showHit(updated);
				}
			});
	}

	private void showHit(NsdServiceInfo resolved) {
		if (resolved.getHost() == null
			&& (resolved.getHostAddresses() == null
				|| resolved.getHostAddresses().isEmpty())) {
			return;
		}
		String addr = resolved.getHost() != null
			? resolved.getHost().getHostAddress()
			: resolved.getHostAddresses().get(0).getHostAddress();
		String hit = addr + ":" + resolved.getPort();
		note("hit " + resolved.getServiceName() + " " + hit);
		foreign = true;
		runOnUiThread(() -> {
			status.setText(hit);
			pin.setVisibility(EditText.VISIBLE);
		});
	}

	private void stopBrowse() {
		if (nsd == null || discovery == null) {
			return;
		}
		try {
			nsd.stopServiceDiscovery(discovery);
		} catch (IllegalArgumentException ignored) {
		}
		discovery = null;
	}

	private void note(String line) {
		Log.i(TAG, line);
		runOnUiThread(() -> {
			log.append(line).append('\n');
			logView.setText(log.toString());
		});
	}
}
