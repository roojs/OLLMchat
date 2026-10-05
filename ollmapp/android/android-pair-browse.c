#include "android-pair-browse.h"

#include <jni.h>

static JavaVM *ollmapp_android_vm = NULL;
static jclass ollmapp_android_pair_cls = NULL;
static jobject ollmapp_android_pair_context = NULL;

JNIEXPORT void JNICALL
Java_org_roojs_ollmchat_androidpoc_PairBrowse_nativeBind (JNIEnv *env,
                                                          jclass cls,
                                                          jobject context)
{
	if ((*env)->GetJavaVM (env, &ollmapp_android_vm) != JNI_OK) {
		g_message ("android pair: GetJavaVM failed");
		return;
	}
	if (ollmapp_android_pair_cls != NULL) {
		(*env)->DeleteGlobalRef (env, ollmapp_android_pair_cls);
	}
	ollmapp_android_pair_cls = (*env)->NewGlobalRef (env, cls);
	if (ollmapp_android_pair_context != NULL) {
		(*env)->DeleteGlobalRef (env, ollmapp_android_pair_context);
	}
	ollmapp_android_pair_context = (*env)->NewGlobalRef (env, context);
	g_message ("android pair: bound");
}

static JNIEnv *
ollmapp_android_jni_env (void)
{
	JNIEnv *env = NULL;

	if (ollmapp_android_vm == NULL) {
		g_message ("android pair: JavaVM not bound");
		return NULL;
	}
	if ((*ollmapp_android_vm)->GetEnv (ollmapp_android_vm, (void **) &env,
		JNI_VERSION_1_6) == JNI_OK) {
		return env;
	}
	if ((*ollmapp_android_vm)->AttachCurrentThread (ollmapp_android_vm, &env,
		NULL) != JNI_OK) {
		g_message ("android pair: attach failed");
		return NULL;
	}
	return env;
}

static gboolean
ollmapp_android_pair_ready (JNIEnv **env_out)
{
	JNIEnv *env;

	*env_out = NULL;
	env = ollmapp_android_jni_env ();
	if (env == NULL || ollmapp_android_pair_cls == NULL
		|| ollmapp_android_pair_context == NULL) {
		g_message ("android pair: browse not bound");
		return FALSE;
	}
	*env_out = env;
	return TRUE;
}

void
ollmapp_android_pair_browse_start (GtkWindow *window)
{
	JNIEnv *env = NULL;
	jmethodID mid;

	(void) window;
	if (!ollmapp_android_pair_ready (&env)) {
		return;
	}
	mid = (*env)->GetStaticMethodID (env, ollmapp_android_pair_cls, "start",
		"(Landroid/content/Context;)V");
	if (mid != NULL && !(*env)->ExceptionCheck (env)) {
		(*env)->CallStaticVoidMethod (env, ollmapp_android_pair_cls, mid,
			ollmapp_android_pair_context);
	}
	if ((*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
	}
}

char *
ollmapp_android_pair_browse_poll (void)
{
	JNIEnv *env;
	jmethodID mid;
	jstring value;
	const char *utf;
	char *copy;

	env = ollmapp_android_jni_env ();
	if (env == NULL || ollmapp_android_pair_cls == NULL) {
		return g_strdup ("");
	}
	mid = (*env)->GetStaticMethodID (env, ollmapp_android_pair_cls, "poll",
		"()Ljava/lang/String;");
	if (mid == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		return g_strdup ("");
	}
	value = (*env)->CallStaticObjectMethod (env, ollmapp_android_pair_cls, mid);
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
	jmethodID mid;

	(void) window;
	if (!ollmapp_android_pair_ready (&env)) {
		return;
	}
	mid = (*env)->GetStaticMethodID (env, ollmapp_android_pair_cls, "stop",
		"(Landroid/content/Context;)V");
	if (mid != NULL && !(*env)->ExceptionCheck (env)) {
		(*env)->CallStaticVoidMethod (env, ollmapp_android_pair_cls, mid,
			ollmapp_android_pair_context);
	}
	if ((*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
	}
}
