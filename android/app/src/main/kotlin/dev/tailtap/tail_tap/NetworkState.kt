package dev.tailtap.app
import android.content.Context
import android.net.ConnectivityManager
import org.json.JSONArray
import org.json.JSONObject

object NetworkState {
    fun refresh(context: Context) {
        val manager = context.getSystemService(ConnectivityManager::class.java)
        val snapshot = JSONArray()
        snapshot.put(JSONObject().put("name","lo").put("index",1).put("mtu",65536).put("loopback",true).put("addresses",JSONArray(listOf("127.0.0.1/8","::1/128"))))
        manager.allNetworks.forEachIndexed { index, network ->
            val link = manager.getLinkProperties(network) ?: return@forEachIndexed
            val name = link.interfaceName ?: return@forEachIndexed
            val addresses = link.linkAddresses.map { "${it.address.hostAddress?.substringBefore('%')}/${it.prefixLength}" }
            snapshot.put(JSONObject().put("name",name).put("index",index+2).put("mtu",if(link.mtu>0)link.mtu else 1500).put("loopback",false).put("addresses",JSONArray(addresses)))
        }
        val error=NativeCore.interfaces(snapshot.toString())
        check(error.isEmpty()) { error }
    }
}
