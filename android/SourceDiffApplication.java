package org.roojs.ollmchat.sourcediff;

import org.gtk.android.RuntimeApplication;
import org.roojs.ollmchat.androidpoc.PairBrowse;

public class SourceDiffApplication extends RuntimeApplication {
	@Override
	public void onCreate() {
		super.onCreate();
		PairBrowse.bindLibrary(this, "oc-test-source-diff");
	}
}
