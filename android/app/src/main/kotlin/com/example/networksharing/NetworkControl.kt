package com.example.networksharing

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiNetworkSpecifier
import android.net.wifi.WifiNetworkSuggestion
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class NetworkControl(private val activity: Activity) {
    private val handler = Handler(Looper.getMainLooper())
    private val connectivity = activity.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private var wifiCallback: ConnectivityManager.NetworkCallback? = null
    private var wifiResult: MethodChannel.Result? = null
    private var pendingWifi: Pair<MethodCall, MethodChannel.Result>? = null
    private var disposed = false
    private var rootBusy = false
    private var wifiTarget: String? = null
    private var wifiPoll: Runnable? = null

    fun hotspot(operation: String, result: MethodChannel.Result) {
        if (rootBusy) { result.error("busy", "Hotspot operation pending", null); return }
        rootBusy = true
        Thread {
            var response: Map<String, Any?>? = null
            try {
                val apk = activity.applicationInfo.sourceDir
                val process = ProcessBuilder("su", "-c", "CLASSPATH=" + apk + " app_process /system/bin com.example.networksharing.RootHotspot " + operation)
                    .redirectErrorStream(true).start()
                // Drain concurrently: a full pipe must never deadlock a root operation.
                val output = StringBuilder()
                val reader = Thread {
                    process.inputStream.bufferedReader().useLines { lines ->
                        lines.forEach { line -> if (output.length < 16384) output.append(line).append('\n') }
                    }
                }.apply { start() }
                if (!process.waitFor(28, TimeUnit.SECONDS)) {
                    process.destroyForcibly()
                    throw IllegalStateException("Root permission or helper timeout")
                }
                reader.join(2000)
                val jsonLine = output.toString().lineSequence().lastOrNull { it.startsWith("{") }
                val json = jsonLine?.let { JSONObject(it) }
                response = if (json != null) json.keys().asSequence().associateWith { key ->
                    json.opt(key).takeUnless { it == JSONObject.NULL }
                } else mapOf("success" to false, "message" to "Root helper unavailable, exit=" + process.exitValue())
                android.util.Log.i("NetworkSharing", "root.$operation success=" + response["success"])
            } catch (error: Throwable) {
                response = mapOf("success" to false, "message" to error.toString())
                android.util.Log.w("NetworkSharing", "root.$operation failed=" + error.javaClass.simpleName)
            }
            handler.post {
                rootBusy = false
                if (disposed) { result.error("activity_destroyed", "Activity destroyed", null); return@post }
                if (response?.get("success") == true || operation != "startHotspot") result.success(response)
                else systemHotspot(result, response?.get("message")?.toString() ?: "Root unavailable")
            }
        }.start()
    }

    private fun systemHotspot(result: MethodChannel.Result, rootError: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            result.success(mapOf("success" to false, "message" to "$rootError；请在系统设置手动开启热点。"))
            return
        }
        try {
            val manager = activity.getSystemService("tethering") as android.net.TetheringManager
            val request = android.net.TetheringManager.TetheringRequest.Builder(android.net.TetheringManager.TETHERING_WIFI).build()
            manager.startTethering(request, activity.mainExecutor, object : android.net.TetheringManager.StartTetheringCallback {
                override fun onTetheringStarted() {
                    result.success(mapOf("success" to true, "enabled" to true,
                        "message" to "系统 API 已确认热点已启动；若无法读取凭据，请在 Debug 表单手动填写并发送。"))
                }
                override fun onTetheringFailed(error: Int) {
                    result.success(mapOf("success" to false, "message" to "$rootError；系统热点启动错误码=$error"))
                }
            })
        } catch (error: Throwable) {
            android.util.Log.w("NetworkSharing", "hotspot.system_fallback_denied type=" + error.javaClass.simpleName)
            result.success(mapOf("success" to false, "message" to "$rootError；系统 API 拒绝应用启动热点：${error.javaClass.simpleName}。仅修改系统设置权限不足以授予 tethering 权限。"))
        }
    }

    fun connectWifi(call: MethodCall, result: MethodChannel.Result) {
        if (pendingWifi != null || wifiResult != null) { result.error("busy", "Wi-Fi request pending", null); return }
        if (Build.VERSION.SDK_INT < 29) { result.error("unsupported", "Wi-Fi API needs Android 10+", null); return }
        val required = mutableListOf(Manifest.permission.ACCESS_FINE_LOCATION)
        if (Build.VERSION.SDK_INT >= 31) required.add(Manifest.permission.ACCESS_COARSE_LOCATION)
        if (Build.VERSION.SDK_INT >= 33) required.add(Manifest.permission.NEARBY_WIFI_DEVICES)
        val missing = required.filter { activity.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isNotEmpty()) {
            pendingWifi = Pair(call, result)
            activity.requestPermissions(missing.toTypedArray(), 4080)
            return
        }
        val ssid = call.argument<String>("ssid") ?: ""
        val password = call.argument<String>("password") ?: ""
        try {
            if (ssid.toByteArray().size !in 1..32) error("SSID must have 1-32 UTF-8 bytes")
            if (password.isNotEmpty() && password.length !in 8..63) error("WPA2 password must have 8-63 characters")
            if (Build.VERSION.SDK_INT >= 30) {
                // Saved-network approval makes the hotspot eligible as the
                // system Internet network. A specifier is a local-only link.
                val suggestion = WifiNetworkSuggestion.Builder().setSsid(ssid).apply {
                    if (password.isNotEmpty()) setWpa2Passphrase(password)
                }.build()
                wifiResult = result
                wifiTarget = ssid
                val intent = Intent(Settings.ACTION_WIFI_ADD_NETWORKS)
                    .putParcelableArrayListExtra(Settings.EXTRA_WIFI_NETWORK_LIST, arrayListOf(suggestion))
                activity.startActivityForResult(intent, 4081)
                return
            }
            wifiCallback?.let { runCatching { connectivity.unregisterNetworkCallback(it) } }
            val spec = WifiNetworkSpecifier.Builder().setSsid(ssid).apply {
                if (password.isNotEmpty()) setWpa2Passphrase(password)
            }.build()
            val request = NetworkRequest.Builder().addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).setNetworkSpecifier(spec).build()
            val callback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) { handler.post {
                    wifiResult?.success(mapOf("success" to true, "message" to "系统已批准并连接目标 Wi-Fi。"))
                    wifiResult = null
                } }
                override fun onUnavailable() { handler.post {
                    wifiResult?.success(mapOf("success" to false, "message" to "Wi-Fi 请求被拒绝或超时。"))
                    wifiResult = null
                    wifiCallback?.let { runCatching { connectivity.unregisterNetworkCallback(it) } }
                    wifiCallback = null
                } }
                override fun onLost(network: Network) {
                    android.util.Log.i("NetworkSharing", "wifi.network_lost")
                }
            }
            wifiCallback = callback
            wifiResult = result
            connectivity.requestNetwork(request, callback, 30000)
        } catch (error: Throwable) {
            wifiResult = null
            result.error("wifi_connect_failed", error.toString(), null)
        }
    }

    @Suppress("DEPRECATION")
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != 4081) return false
        if (resultCode != Activity.RESULT_OK) {
            wifiResult?.success(mapOf("success" to false, "message" to "系统 Wi-Fi 保存/连接请求被取消。"))
            wifiResult = null
            wifiTarget = null
            return true
        }
        val statuses = data?.getIntegerArrayListExtra(Settings.EXTRA_WIFI_NETWORK_RESULT_LIST)
        android.util.Log.i("NetworkSharing", "wifi.save_result codes=" + statuses)
        if (statuses?.any { it == 1 } == true) {
            wifiResult?.success(mapOf("success" to false, "message" to "系统拒绝保存目标 Wi-Fi。"))
            wifiResult = null
            return true
        }
        var attempts = 0
        val poll = object : Runnable {
            override fun run() {
                if (disposed || wifiResult == null) return
                val wifi = activity.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                val actual = runCatching { wifi.connectionInfo.ssid.trim('"') }.getOrNull()
                if (actual == wifiTarget) {
                    wifiResult?.success(mapOf("success" to true, "message" to "目标 Wi-Fi 已成为系统连接网络。"))
                    wifiResult = null
                    wifiTarget = null
                    wifiPoll = null
                } else if (++attempts >= 25) {
                    wifiResult?.success(mapOf("success" to false, "message" to "网络已保存，但未确认切换成功；请检查 Wi-Fi、定位服务和密码。"))
                    wifiResult = null
                    wifiTarget = null
                    wifiPoll = null
                } else {
                    handler.postDelayed(this, 1000)
                }
            }
        }
        wifiPoll = poll
        handler.post(poll)
        return true
    }

    fun onPermissionsResult(requestCode: Int, grants: IntArray): Boolean {
        if (requestCode != 4080) return false
        val pending = pendingWifi
        pendingWifi = null
        if (pending != null) {
            if (grants.isNotEmpty() && grants.all { it == PackageManager.PERMISSION_GRANTED }) connectWifi(pending.first, pending.second)
            else pending.second.error("wifi_permission_denied", "Wi-Fi permission denied", null)
        }
        return true
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        wifiPoll?.let { handler.removeCallbacks(it) }
        wifiCallback?.let { runCatching { connectivity.unregisterNetworkCallback(it) } }
        wifiResult?.error("activity_destroyed", "Wi-Fi interrupted", null)
        wifiResult = null
        wifiCallback = null
        wifiTarget = null
        pendingWifi?.second?.error("activity_destroyed", "Permission interrupted", null)
        pendingWifi = null
    }

}
