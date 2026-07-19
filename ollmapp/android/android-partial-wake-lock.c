#include "android-partial-wake-lock.h"

#ifdef __ANDROID__

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

	if (ollmapp_android_vm == NULL) {
		return NULL;
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

#else /* !__ANDROID__ */

void
ollmapp_android_set_partial_wake_lock (GtkWindow *window, gboolean enable)
{
	(void) window;
	(void) enable;
}

void
ollmapp_android_set_streaming_foreground (GtkWindow *window, gboolean enable)
{
	(void) window;
	(void) enable;
}

#endif
