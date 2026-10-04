#include "android-pair-browse.h"

#include <dlfcn.h>
#include <jni.h>
#include <gdk/android/gdkandroid.h>

static JavaVM *ollmapp_android_vm = NULL;

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
		(*env)->ExceptionClear (env);
		(*env)->DeleteLocalRef (env, activity);
		return;
	}
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
	if (env == NULL) {
		return g_strdup ("");
	}
	cls = (*env)->FindClass (env, "org/roojs/ollmchat/androidpoc/PairBrowse");
	if (cls == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		if (cls != NULL) {
			(*env)->DeleteLocalRef (env, cls);
		}
		return g_strdup ("");
	}
	mid = (*env)->GetStaticMethodID (env, cls, "poll",
		"()Ljava/lang/String;");
	if (mid == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		(*env)->DeleteLocalRef (env, cls);
		return g_strdup ("");
	}
	value = (*env)->CallStaticObjectMethod (env, cls, mid);
	if (value == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		(*env)->DeleteLocalRef (env, cls);
		return g_strdup ("");
	}
	utf = (*env)->GetStringUTFChars (env, value, NULL);
	copy = g_strdup (utf != NULL ? utf : "");
	if (utf != NULL) {
		(*env)->ReleaseStringUTFChars (env, value, utf);
	}
	(*env)->DeleteLocalRef (env, value);
	(*env)->DeleteLocalRef (env, cls);
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
