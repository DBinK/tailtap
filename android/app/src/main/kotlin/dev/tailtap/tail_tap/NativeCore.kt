package dev.tailtap.app
object NativeCore {
    init { System.loadLibrary("tailtap-jni") }
    external fun interfaces(json: String): String
    external fun start(id: String, config: String): String
    external fun stop(id: String): Int
    external fun poll(): String
    external fun control(id: String, command: String): Int
}
