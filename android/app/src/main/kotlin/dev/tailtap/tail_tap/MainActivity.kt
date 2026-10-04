package dev.tailtap.app
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val handler = Handler(Looper.getMainLooper())
    private val fileIo = Executors.newSingleThreadExecutor()
    private lateinit var destinationPicker: ActivityResultLauncher<Uri?>
    private var destinationResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        destinationPicker = registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
            val result = destinationResult
            destinationResult = null
            if (uri == null) {
                result?.success(null)
            } else {
                val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                contentResolver.takePersistableUriPermission(uri, flags)
                result?.success(uri.toString())
            }
        }
    }
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
                    "pickDestination" -> {
                        if (destinationResult != null) result.error("busy", "目录选择器已打开", null)
                        else {
                            destinationResult = result
                            destinationPicker.launch(null)
                        }
                    }
                    "copyToTree" -> {
                        val treeUri = Uri.parse(call.argument<String>("treeUri")!!)
                        val sourcePath = call.argument<String>("sourcePath")!!
                        val requestedName = call.argument<String>("name")!!
                        fileIo.execute {
                            try {
                                val name = copyToTree(treeUri, sourcePath, requestedName)
                                handler.post { result.success(name) }
                            } catch (e: Throwable) {
                                handler.post { result.error("save", e.message ?: "无法保存到所选目录", null) }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch(e: Throwable) { result.error("core",e.message ?: "原生核心不可用",null) }
        }
    }

    private fun uniqueName(root: DocumentFile, requested: String): String {
        if (!root.findFile(requested).let { it?.exists() == true }) return requested
        val dot = requested.lastIndexOf('.')
        val stem = if (dot > 0) requested.substring(0, dot) else requested
        val extension = if (dot > 0) requested.substring(dot) else ""
        var index = 2
        while (root.findFile("$stem ($index)$extension")?.exists() == true) index++
        return "$stem ($index)$extension"
    }

    private fun copyToTree(treeUri: Uri, sourcePath: String, requestedName: String): String {
        val source = java.io.File(sourcePath)
        val root = DocumentFile.fromTreeUri(this, treeUri)
            ?: throw IllegalStateException("无法访问所选目录")
        val name = uniqueName(root, requestedName)
        val target = root.createFile("application/octet-stream", name)
            ?: throw IllegalStateException("无法在所选目录创建文件")
        try {
            contentResolver.openOutputStream(target.uri, "w")!!.use { output ->
                source.inputStream().use { input -> input.copyTo(output) }
            }
        } catch (e: Throwable) {
            target.delete()
            throw e
        }
        return target.name ?: name
    }
}
