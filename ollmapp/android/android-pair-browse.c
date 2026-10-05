#include "android-pair-browse.h"

#include <jni.h>
#include <gdk/android/gdkandroid.h>

extern JNIEnv *gdk_android_ollmchat_jni_env (void);

static jclass ollmapp_android_pair_cls = NULL;

static JNIEnv *
ollmapp_android_jni_env (void)
{
	JNIEnv *env = gdk_android_ollmchat_jni_env ();
	if (env == NULL) {
		g_message ("android jni: GTK has no JNIEnv");
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

static jobject
ollmapp_android_activity (GtkWindow *window, JNIEnv **env_out)
{
	GdkSurface *surface;
	jobject activity;
	JNIEnv *env;

	*env_out = NULL;
	if (window == NULL) {
		return NULL;
	}
	surface = gtk_native_get_surface (GTK_NATIVE (window));
	if (surface == NULL || !GDK_IS_ANDROID_TOPLEVEL (surface)) {
		return NULL;
	}
	activity = gdk_android_toplevel_get_activity (GDK_ANDROID_TOPLEVEL (surface));
	if (activity == NULL) {
		return NULL;
	}
	env = ollmapp_android_jni_env ();
	if (env == NULL) {
		return NULL;
	}
	*env_out = env;
	return activity;
}

void
ollmapp_android_pair_browse_start (GtkWindow *window)
{
	JNIEnv *env = NULL;
	jobject activity;
	jclass cls;
	jmethodID mid;

	activity = ollmapp_android_activity (window, &env);
	if (activity == NULL) {
		return;
	}
	cls = ollmapp_android_load_class (env, activity,
		"org.roojs.ollmchat.androidpoc.PairBrowse");
	if (cls == NULL || (*env)->ExceptionCheck (env)) {
		g_message ("android pair: PairBrowse class missing");
		(*env)->ExceptionClear (env);
		(*env)->DeleteLocalRef (env, activity);
		return;
	}
	if (ollmapp_android_pair_cls != NULL) {
		(*env)->DeleteGlobalRef (env, ollmapp_android_pair_cls);
	}
	ollmapp_android_pair_cls = (*env)->NewGlobalRef (env, cls);
	mid = (*env)->GetStaticMethodID (env, cls, "start",
		"(Landroid/content/Context;)V");
	if (mid != NULL && !(*env)->ExceptionCheck (env)) {
		(*env)->CallStaticVoidMethod (env, cls, mid, activity);
	}
	if ((*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
	}
	(*env)->DeleteLocalRef (env, cls);
	(*env)->DeleteLocalRef (env, activity);
}

char *
ollmapp_android_pair_browse_poll (void)
{
	JNIEnv *env;
	jclass cls;
	jmethodID mid;
	jstring value;
	const char *utf;
	char *copy;

	env = ollmapp_android_jni_env ();
	if (env == NULL || ollmapp_android_pair_cls == NULL) {
		return g_strdup ("");
	}
	cls = ollmapp_android_pair_cls;
	mid = (*env)->GetStaticMethodID (env, cls, "poll",
		"()Ljava/lang/String;");
	if (mid == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		return g_strdup ("");
	}
	value = (*env)->CallStaticObjectMethod (env, cls, mid);
	if (value == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		return g_strdup ("");
	}
	utf = (*env)->GetStringUTFChars (env, value, NULL);
	copy = g_strdup (utf != NULL ? utf : "");
	if (utf != NULL) {
		(*env)->ReleaseStringUTFChars (env, value, utf);
	}
	(*env)->DeleteLocalRef (env, value);
	return copy;
}

void
ollmapp_android_pair_browse_stop (GtkWindow *window)
{
	JNIEnv *env = NULL;
	jobject activity;
	jclass cls;
	jmethodID mid;

	activity = ollmapp_android_activity (window, &env);
	if (activity == NULL) {
		return;
	}
	cls = ollmapp_android_load_class (env, activity,
		"org.roojs.ollmchat.androidpoc.PairBrowse");
	if (cls == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		(*env)->DeleteLocalRef (env, activity);
		return;
	}
	mid = (*env)->GetStaticMethodID (env, cls, "stop",
		"(Landroid/content/Context;)V");
	if (mid != NULL && !(*env)->ExceptionCheck (env)) {
		(*env)->CallStaticVoidMethod (env, cls, mid, activity);
	}
	if ((*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
	}
	(*env)->DeleteLocalRef (env, cls);
	(*env)->DeleteLocalRef (env, activity);
}
