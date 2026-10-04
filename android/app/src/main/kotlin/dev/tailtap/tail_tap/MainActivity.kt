package dev.tailtap.app
import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val handler = Handler(Looper.getMainLooper())
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            val diagnostic = java.io.File(filesDir, "native-diagnostic.txt")
            val descriptor = android.os.ParcelFileDescriptor.open(diagnostic, android.os.ParcelFileDescriptor.MODE_CREATE or android.os.ParcelFileDescriptor.MODE_TRUNCATE or android.os.ParcelFileDescriptor.MODE_WRITE_ONLY)
            android.system.Os.dup2(descriptor.fileDescriptor, 2)
            descriptor.close()
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger,"dev.tailtap/events").setStreamHandler(object: EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) { TunnelService.sendEvent = { sink.success(it) } }
            override fun onCancel(arguments: Any?) { TunnelService.sendEvent = null }
        })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,"dev.tailtap/core").setMethodCallHandler { call,result ->
            try {
                when(call.method) {
                    "start" -> {
                        val id = call.argument<String>("id")!!
                        val config = call.argument<Map<String,Any?>>("config")!!
                        NetworkState.refresh(this)
                        val error = NativeCore.start(id,JSONObject(config).toString())
                        if(error.isNotEmpty()) result.error("start",error,null) else {
                            TunnelService.ids.add(id)
                            TunnelService.configs[id] = config
                            ContextCompat.startForegroundService(this,Intent(this,TunnelService::class.java))
                            if (android.os.Build.VERSION.SDK_INT >= 33 && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                                requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 1001)
                            }
                            result.success(null)
                        }
                    }
                    "stop" -> {
                        val id=call.argument<String>("id")!!
                        TunnelService.executor.execute {
                            val success=NativeCore.stop(id)==1
                            handler.post {
                                if(success) {
                                    TunnelService.ids.remove(id)
                                    TunnelService.configs.remove(id)
                                    TunnelService.sendEvent?.invoke(mapOf("id" to id,"state" to "stopped"))
                                    if(TunnelService.ids.isEmpty()) stopService(Intent(this,TunnelService::class.java))
                                    result.success(null)
                                } else result.error("stop","核心仍在清理资源，请重试停止",null)
                            }
                        }
                    }
                    "snapshot" -> result.success(TunnelService.snapshot())
                    "control" -> result.success(NativeCore.control(call.argument<String>("id")!!, JSONObject(call.argument<Map<String,Any?>>("command")!!).toString()) == 1)
                    else -> result.notImplemented()
                }
            } catch(e: Throwable) { result.error("core",e.message ?: "原生核心不可用",null) }
        }
    }
}
