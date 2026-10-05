package org.roojs.ollmchat.androidpoc;

import org.gtk.android.RuntimeApplication;

public class OllmApplication extends RuntimeApplication {
	@Override
	public void onCreate() {
		super.onCreate();
		PairBrowse.bind(this);
	}
}
