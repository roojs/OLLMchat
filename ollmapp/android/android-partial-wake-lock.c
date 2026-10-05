#include "android-partial-wake-lock.h"

#include <dlfcn.h>
#include <jni.h>
#include <gdk/android/gdkandroid.h>

static JavaVM *ollmapp_android_vm = NULL;

JNIEXPORT jint
JNI_OnLoad (JavaVM *vm, void *reserved)
{
	(void) reserved;
	ollmapp_android_vm = vm;
	return JNI_VERSION_1_6;
}

static JNIEnv *
ollmapp_android_jni_env (void)
{
	JNIEnv *env = NULL;
	jsize vm_count = 0;

	/* GTK loads this .so with g_module_open, which does not run JNI_OnLoad. */
	if (ollmapp_android_vm == NULL) {
		void *helper = dlopen ("libnativehelper.so", RTLD_NOW | RTLD_NOLOAD);
		jint (*get_vms) (JavaVM **, jsize, jsize *) = NULL;

		if (helper != NULL) {
			get_vms = dlsym (helper, "JNI_GetCreatedJavaVMs");
		}
		/* Arm translation loads the x86_64 helper in another
		 * linker namespace, so NOLOAD misses it. Load the
		 * arm64 helper, which forwards to that VM. */
		if (helper == NULL) {
			helper = dlopen ("libnativehelper.so", RTLD_NOW);
		}
		if (get_vms == NULL && helper != NULL) {
			get_vms = dlsym (helper, "JNI_GetCreatedJavaVMs");
		}
		if (get_vms == NULL) {
			get_vms = dlsym (RTLD_DEFAULT, "JNI_GetCreatedJavaVMs");
		}
		if (get_vms == NULL
			|| get_vms (&ollmapp_android_vm, 1, &vm_count) != JNI_OK
			|| vm_count < 1) {
			g_message ("android jni: no JavaVM helper=%p get_vms=%p count=%d",
				helper, (void *) get_vms, (int) vm_count);
			ollmapp_android_vm = NULL;
			return NULL;
		}
	}
	if ((*ollmapp_android_vm)->GetEnv (ollmapp_android_vm, (void **) &env,
		JNI_VERSION_1_6) == JNI_OK) {
		return env;
	}
	if ((*ollmapp_android_vm)->AttachCurrentThread (ollmapp_android_vm, &env,
		NULL) != JNI_OK) {
		return NULL;
	}
	return env;
}

static jclass
ollmapp_android_load_class (JNIEnv *env, jobject activity, const char *name)
{
	jclass activity_cls;
	jmethodID get_cl;
	jobject loader;
	jclass loader_cls;
	jmethodID load_class;
	jstring jname;
	jclass result;

	activity_cls = (*env)->GetObjectClass (env, activity);
	get_cl = (*env)->GetMethodID (env, activity_cls, "getClassLoader",
		"()Ljava/lang/ClassLoader;");
	loader = (*env)->CallObjectMethod (env, activity, get_cl);
	loader_cls = (*env)->GetObjectClass (env, loader);
	load_class = (*env)->GetMethodID (env, loader_cls, "loadClass",
		"(Ljava/lang/String;)Ljava/lang/Class;");
	jname = (*env)->NewStringUTF (env, name);
	result = (jclass) (*env)->CallObjectMethod (env, loader, load_class, jname);
	(*env)->DeleteLocalRef (env, jname);
	(*env)->DeleteLocalRef (env, loader_cls);
	(*env)->DeleteLocalRef (env, loader);
	(*env)->DeleteLocalRef (env, activity_cls);
	return result;
}

void
ollmapp_android_set_partial_wake_lock (GtkWindow *window, gboolean enable)
{
	GdkSurface *surface;
	jobject activity;
	JNIEnv *env;
	jclass wake_cls;
	jmethodID set_mid;

	if (window == NULL) {
		return;
	}
	surface = gtk_native_get_surface (GTK_NATIVE (window));
	if (surface == NULL || !GDK_IS_ANDROID_TOPLEVEL (surface)) {
		return;
	}
	activity = gdk_android_toplevel_get_activity (GDK_ANDROID_TOPLEVEL (surface));
	if (activity == NULL) {
		return;
	}
	env = ollmapp_android_jni_env ();
	if (env == NULL) {
		return;
	}
	wake_cls = ollmapp_android_load_class (env, activity,
		"org.roojs.ollmchat.androidpoc.PartialWakeLock");
	if (wake_cls == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		(*env)->DeleteLocalRef (env, activity);
		return;
	}
	set_mid = (*env)->GetStaticMethodID (env, wake_cls, "set",
		"(Landroid/content/Context;Z)V");
	if (set_mid == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		(*env)->DeleteLocalRef (env, wake_cls);
		(*env)->DeleteLocalRef (env, activity);
		return;
	}
	(*env)->CallStaticVoidMethod (env, wake_cls, set_mid, activity,
		enable ? JNI_TRUE : JNI_FALSE);
	if ((*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
	}
	(*env)->DeleteLocalRef (env, wake_cls);
	(*env)->DeleteLocalRef (env, activity);
}

void
ollmapp_android_set_streaming_foreground (GtkWindow *window, gboolean enable)
{
	GdkSurface *surface;
	jobject activity;
	JNIEnv *env;
	jclass fg_cls;
	jmethodID set_mid;

	if (window == NULL) {
		return;
	}
	surface = gtk_native_get_surface (GTK_NATIVE (window));
	if (surface == NULL || !GDK_IS_ANDROID_TOPLEVEL (surface)) {
		return;
	}
	activity = gdk_android_toplevel_get_activity (GDK_ANDROID_TOPLEVEL (surface));
	if (activity == NULL) {
		return;
	}
	env = ollmapp_android_jni_env ();
	if (env == NULL) {
		return;
	}
	fg_cls = ollmapp_android_load_class (env, activity,
		"org.roojs.ollmchat.androidpoc.StreamingForeground");
	if (fg_cls == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		(*env)->DeleteLocalRef (env, activity);
		return;
	}
	set_mid = (*env)->GetStaticMethodID (env, fg_cls, "set",
		"(Landroid/content/Context;Z)V");
	if (set_mid == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		(*env)->DeleteLocalRef (env, fg_cls);
		(*env)->DeleteLocalRef (env, activity);
		return;
	}
	(*env)->CallStaticVoidMethod (env, fg_cls, set_mid, activity,
		enable ? JNI_TRUE : JNI_FALSE);
	if ((*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
	}
	(*env)->DeleteLocalRef (env, fg_cls);
	(*env)->DeleteLocalRef (env, activity);
}

gboolean
ollmapp_android_is_tablet (GtkWindow *window)
{
	GdkSurface *surface;
	jobject activity;
	JNIEnv *env;
	jclass activity_cls;
	jmethodID get_resources;
	jobject resources;
	jclass resources_cls;
	jmethodID get_configuration;
	jobject configuration;
	jclass configuration_cls;
	jfieldID sw_field;
	jint sw;

	surface = gtk_native_get_surface (GTK_NATIVE (window));
	if (surface == NULL || !GDK_IS_ANDROID_TOPLEVEL (surface)) {
		g_message ("android tablet: surface=%p android_toplevel=%d",
			(void *) surface,
			surface != NULL && GDK_IS_ANDROID_TOPLEVEL (surface));
		return FALSE;
	}
	activity = gdk_android_toplevel_get_activity (GDK_ANDROID_TOPLEVEL (surface));
	if (activity == NULL) {
		g_message ("android tablet: activity is null");
		return FALSE;
	}
	env = ollmapp_android_jni_env ();
	if (env == NULL) {
		g_message ("android tablet: jni env is null");
		return FALSE;
	}
	activity_cls = (*env)->GetObjectClass (env, activity);
	get_resources = (*env)->GetMethodID (env, activity_cls, "getResources",
		"()Landroid/content/res/Resources;");
	resources = (*env)->CallObjectMethod (env, activity, get_resources);
	resources_cls = (*env)->GetObjectClass (env, resources);
	get_configuration = (*env)->GetMethodID (env, resources_cls,
		"getConfiguration", "()Landroid/content/res/Configuration;");
	configuration = (*env)->CallObjectMethod (env, resources, get_configuration);
	configuration_cls = (*env)->GetObjectClass (env, configuration);
	sw_field = (*env)->GetFieldID (env, configuration_cls,
		"smallestScreenWidthDp", "I");
	sw = (*env)->GetIntField (env, configuration, sw_field);
	g_message ("android tablet: smallestScreenWidthDp=%d", (int) sw);
	(*env)->DeleteLocalRef (env, configuration_cls);
	(*env)->DeleteLocalRef (env, configuration);
	(*env)->DeleteLocalRef (env, resources_cls);
	(*env)->DeleteLocalRef (env, resources);
	(*env)->DeleteLocalRef (env, activity_cls);
	(*env)->DeleteLocalRef (env, activity);
	return sw >= 600;
}

void
ollmapp_android_lock_landscape (GtkWindow *window)
{
	GdkSurface *surface;
	jobject activity;
	JNIEnv *env;
	jclass activity_cls;
	jmethodID set_mid;

	surface = gtk_native_get_surface (GTK_NATIVE (window));
	if (surface == NULL || !GDK_IS_ANDROID_TOPLEVEL (surface)) {
		return;
	}
	activity = gdk_android_toplevel_get_activity (GDK_ANDROID_TOPLEVEL (surface));
	if (activity == NULL) {
		return;
	}
	env = ollmapp_android_jni_env ();
	if (env == NULL) {
		return;
	}
	activity_cls = (*env)->GetObjectClass (env, activity);
	set_mid = (*env)->GetMethodID (env, activity_cls,
		"setRequestedOrientation", "(I)V");
	/* ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE */
	(*env)->CallVoidMethod (env, activity, set_mid, 6);
	if ((*env)->ExceptionCheck (env)) {
		(*env)->ExceptionDescribe (env);
		(*env)->ExceptionClear (env);
		g_message ("android landscape: setRequestedOrientation threw");
	} else {
		g_message ("android landscape: requested SENSOR_LANDSCAPE");
	}
	(*env)->DeleteLocalRef (env, activity_cls);
	(*env)->DeleteLocalRef (env, activity);
}
