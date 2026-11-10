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
            var requestedSsid: String? = null
            var requestedPassword: String? = null
            var configurationSource: String? = null
            var configurationReadContext: String? = null
            if (operation == "startHotspot") {
                val supplied = System.`in`.bufferedReader().readLine()?.takeIf { it.isNotBlank() }
                val saved = if (supplied != null) {
                    configurationReadContext = "application"
                    SavedHotspotConfiguration.decode(supplied)
                } else {
                    configurationReadContext = "root_system"
                    SavedHotspotConfiguration.read(wifi)
                }
                requestedSsid = saved.ssid
                requestedPassword = saved.password
                val start = SavedHotspotConfiguration.prepare(wifi, saved)
                configurationSource = start.source
                val latch = CountDownLatch(1)
                var failure: Int? = null
                manager.startTethering(start.request, executor, object : TetheringManager.StartTetheringCallback {
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
                val current = SavedHotspotConfiguration.read(wifi)
                val actualSsid = current.ssid
                val actualPassword = current.password
                if (operation == "startHotspot" &&
                    (actualSsid != requestedSsid || actualPassword != requestedPassword)) {
                    runCatching {
                        manager.javaClass.getMethod("stopTethering", Int::class.javaPrimitiveType)
                            .invoke(manager, TetheringManager.TETHERING_WIFI)
                    }
                    error("Started hotspot does not match the saved system configuration")
                }
                json.put("ssid", actualSsid)
                json.put("password", actualPassword)
                if (operation == "startHotspot") {
                    json.put("configurationSource", configurationSource)
                    json.put("configurationReadContext", configurationReadContext)
                }
            } catch (error: Exception) {
                // Never fall back to unrelated legacy credentials after a
                // start verification failure. The receiver would join another AP.
                if (operation == "startHotspot") throw error
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
