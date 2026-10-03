#include <jni.h>
#include "libtailtap.h"
JNIEXPORT jstring JNICALL Java_dev_tailtap_app_NativeCore_start(JNIEnv *env, jobject self, jstring id, jstring config) {
 const char *i=(*env)->GetStringUTFChars(env,id,0), *c=(*env)->GetStringUTFChars(env,config,0);
 char *result=StartTask((char *)i,(char *)c);
 jstring value=(*env)->NewStringUTF(env,result);FreeString(result);
 (*env)->ReleaseStringUTFChars(env,id,i);(*env)->ReleaseStringUTFChars(env,config,c);return value;
}
JNIEXPORT jint JNICALL Java_dev_tailtap_app_NativeCore_stop(JNIEnv *env,jobject self,jstring id) {
 const char *i=(*env)->GetStringUTFChars(env,id,0);int result=StopTask((char *)i);(*env)->ReleaseStringUTFChars(env,id,i);return result;
}
JNIEXPORT jstring JNICALL Java_dev_tailtap_app_NativeCore_poll(JNIEnv *env,jobject self) {
 char *result=PollEvents();jstring value=(*env)->NewStringUTF(env,result);FreeString(result);return value;
}
JNIEXPORT jstring JNICALL Java_dev_tailtap_app_NativeCore_interfaces(JNIEnv *env,jobject self,jstring json) {
 const char *raw=(*env)->GetStringUTFChars(env,json,0);char *result=SetInterfaces((char *)raw);
 jstring value=(*env)->NewStringUTF(env,result);FreeString(result);(*env)->ReleaseStringUTFChars(env,json,raw);return value;
}
