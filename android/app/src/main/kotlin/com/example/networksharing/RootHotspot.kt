package com.example.networksharing

import android.content.Context
import android.net.TetheringManager
import android.net.wifi.WifiManager
import android.os.Looper
import org.json.JSONObject
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Runs via app_process under su, independently of the Activity and UI thread. */
object RootHotspot {
    @JvmStatic
    fun main(args: Array<String>) {
        val executor = Executors.newSingleThreadExecutor()
        try {
            // A root app_process has no application hidden-API exemption by
            // default. Allow the framework calls needed by the system context.
            runCatching {
                val runtimeClass = Class.forName("dalvik.system.VMRuntime")
                val runtime = runtimeClass.getDeclaredMethod("getRuntime").invoke(null)
                runtimeClass.getDeclaredMethod("setHiddenApiExemptions", Array<String>::class.java)
                    .invoke(runtime, arrayOf("L") as Any)
            }
            if (Looper.getMainLooper() == null) Looper.prepareMainLooper()
            val activityThread = Class.forName("android.app.ActivityThread")
            val thread = activityThread.getDeclaredMethod("systemMain").invoke(null)
            val context = activityThread.getDeclaredMethod("getSystemContext").invoke(thread) as Context
            val wifi = context.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val manager = context.getSystemService("tethering") as TetheringManager
            val operation = args.firstOrNull() ?: "getHotspot"
            if (operation == "startHotspot") {
                val latch = CountDownLatch(1)
                var failure: Int? = null
                val request = TetheringManager.TetheringRequest.Builder(TetheringManager.TETHERING_WIFI).build()
                manager.startTethering(request, executor, object : TetheringManager.StartTetheringCallback {
                    override fun onTetheringStarted() { latch.countDown() }
                    override fun onTetheringFailed(error: Int) { failure = error; latch.countDown() }
                })
                if (!latch.await(20, TimeUnit.SECONDS)) error("Tethering callback timeout")
                failure?.let { error("Tethering rejected: $it") }
            } else if (operation == "stopHotspot") {
                manager.javaClass.getMethod("stopTethering", Int::class.javaPrimitiveType)
                    .invoke(manager, TetheringManager.TETHERING_WIFI)
                Thread.sleep(800)
            }
            var state = wifi.javaClass.getMethod("getWifiApState").invoke(wifi) as Int
            if (operation == "startHotspot") {
                var retries = 0
                while (state != 13 && retries++ < 20) {
                    Thread.sleep(200)
                    state = wifi.javaClass.getMethod("getWifiApState").invoke(wifi) as Int
                }
            }
            val json = JSONObject().put("success", true).put("enabled", state == 13)
                .put("message", "Root tethering state=$state")
            // The framework callback reports current clients when registered.
            // An unsupported callback remains unknown, never an assumed zero.
            if (operation == "getHotspot") runCatching {
                val callbackType = Class.forName("android.net.TetheringManager" + "$" + "TetheringEventCallback")
                val clientsReady = CountDownLatch(1)
                var count: Int? = null
                val callback = java.lang.reflect.Proxy.newProxyInstance(
                    callbackType.classLoader, arrayOf(callbackType)
                ) { proxy, method, values ->
                    when (method.name) {
                        "onClientsChanged" -> {
                            count = (values?.firstOrNull() as? Collection<*>)?.size
                            clientsReady.countDown()
                            null
                        }
                        "hashCode" -> System.identityHashCode(proxy)
                        "equals" -> proxy === values?.firstOrNull()
                        "toString" -> "NetworkSharingClientsCallback"
                        else -> null
                    }
                }
                manager.javaClass.getMethod("registerTetheringEventCallback", java.util.concurrent.Executor::class.java, callbackType)
                    .invoke(manager, executor, callback)
                try {
                    if (clientsReady.await(1500, TimeUnit.MILLISECONDS) && count != null) json.put("clientCount", count)
                } finally {
                    manager.javaClass.getMethod("unregisterTetheringEventCallback", callbackType).invoke(manager, callback)
                }
            }
            if (operation == "startHotspot" && state != 13) error("Hotspot not enabled: $state")
            try {
                val config = wifi.javaClass.getMethod("getSoftApConfiguration").invoke(wifi)
                json.put("ssid", config.javaClass.getMethod("getSsid").invoke(config))
                json.put("password", config.javaClass.getMethod("getPassphrase").invoke(config) ?: "")
            } catch (_: Exception) {
                runCatching {
                    val config = wifi.javaClass.getMethod("getWifiApConfiguration").invoke(wifi)
                    json.put("ssid", config.javaClass.getField("SSID").get(config))
                    json.put("password", config.javaClass.getField("preSharedKey").get(config) ?: "")
                }.onFailure {
                    json.put("message", "Root tethering state=$state; credentials unavailable")
                }
            }
            println(json.toString())
        } catch (error: Throwable) {
            println(JSONObject().put("success", false).put("message", "Root helper: " + error.toString()).toString())
        } finally {
            executor.shutdownNow()
            kotlin.system.exitProcess(0)
        }
    }
}
