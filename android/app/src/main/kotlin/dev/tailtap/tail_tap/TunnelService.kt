package dev.tailtap.app

import android.app.*
import android.content.Intent
import android.os.*
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors

class TunnelService : Service() {
    companion object {
        val ids = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()
        val configs = java.util.concurrent.ConcurrentHashMap<String, Map<String, Any?>>()
        val executor = Executors.newSingleThreadExecutor()
        var sendEvent: ((Map<String, Any?>) -> Unit)? = null
        private val snapshots = mutableMapOf<String, Map<String, Any?>>()
        @Synchronized fun snapshot(): List<Map<String, Any?>> = ids.map { id -> mapOf("id" to id, "config" to configs[id], "state" to "starting") + (snapshots[id] ?: emptyMap()) }
    }
    private val handler = Handler(Looper.getMainLooper())
    private val networkCallback = object : android.net.ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: android.net.Network) { NetworkState.refresh(this@TunnelService) }
        override fun onLost(network: android.net.Network) { NetworkState.refresh(this@TunnelService) }
        override fun onLinkPropertiesChanged(network: android.net.Network, link: android.net.LinkProperties) { NetworkState.refresh(this@TunnelService) }
    }
    private val poll = object : Runnable {
        override fun run() {
            val events = JSONArray(NativeCore.poll())
            for (i in 0 until events.length()) {
                val json = JSONObject(events.getString(i))
                val event = json.keys().asSequence().associateWith { key -> nativeValue(json.get(key)) }
                val id = event["id"] as? String ?: continue
                synchronized(TunnelService::class.java) { snapshots[id] = (snapshots[id] ?: emptyMap()) + event }
                sendEvent?.invoke(event)
                if (event["state"] == "stopped" || event["state"] == "failed" || event["state"] == "conflict") {
                    ids.remove(id)
                    configs.remove(id)
                    synchronized(TunnelService::class.java) { snapshots.remove(id) }
                    if(ids.isEmpty()) stopSelf() else getSystemService(NotificationManager::class.java).notify(1,notification())
                }
            }
            if(ids.isNotEmpty()) handler.postDelayed(this, 300)
        }
    }
    override fun onCreate() {
        super.onCreate()
        getSystemService(android.net.ConnectivityManager::class.java).registerDefaultNetworkCallback(networkCallback)
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("tunnels", "活动连接", NotificationManager.IMPORTANCE_LOW))
        startForeground(1, notification())
        handler.post(poll)
    }
    private fun notification(): Notification {
        val open = PendingIntent.getActivity(this,0,Intent(this, MainActivity::class.java),PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val stop = PendingIntent.getService(this,1,Intent(this,TunnelService::class.java).setAction("stopAll"),PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        return NotificationCompat.Builder(this,"tunnels").setSmallIcon(android.R.drawable.stat_sys_upload_done).setContentTitle("TailTap · ${ids.size} 个活动任务").setContentText("点击返回应用").setContentIntent(open).setOngoing(true).addAction(0,"停止全部",stop).build()
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if(intent?.action == "stopAll") {
            ids.toList().forEach { id -> executor.execute { stopTask(id) } }
        }
        getSystemService(NotificationManager::class.java).notify(1,notification())
        return START_NOT_STICKY
    }
    fun stopTask(id: String): Boolean {
        val success = NativeCore.stop(id) == 1
        if(success) handler.post {
            ids.remove(id)
            configs.remove(id)
            synchronized(TunnelService::class.java) { snapshots.remove(id) }
            sendEvent?.invoke(mapOf("id" to id,"state" to "stopped"))
            if(ids.isEmpty()) stopSelf() else getSystemService(NotificationManager::class.java).notify(1,notification())
        }
        return success
    }
    override fun onDestroy() {
        getSystemService(android.net.ConnectivityManager::class.java).unregisterNetworkCallback(networkCallback)
        handler.removeCallbacksAndMessages(null)
        ids.toList().forEach { id -> executor.execute { NativeCore.stop(id) } }
        ids.clear()
        configs.clear()
        synchronized(TunnelService::class.java) { snapshots.clear() }
        super.onDestroy()
    }
    override fun onTimeout(startId: Int, fgsType: Int) {
        ids.toList().forEach { id ->
            sendEvent?.invoke(mapOf("id" to id, "state" to "failed", "error" to "Android 后台服务时限已到，请重新启动"))
        }
        stopSelf()
    }
    override fun onBind(intent: Intent?): IBinder? = null
    private fun nativeValue(value: Any?): Any? = when(value) {
        null, JSONObject.NULL -> null
        is JSONObject -> value.keys().asSequence().associateWith { nativeValue(value.get(it)) }
        is JSONArray -> (0 until value.length()).map { nativeValue(value.get(it)) }
        else -> value
    }
}
