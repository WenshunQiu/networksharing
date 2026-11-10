package com.example.networksharing

import android.net.TetheringManager
import android.net.wifi.WifiManager
import android.util.Base64
import org.json.JSONObject

/** Keep the complete Settings configuration, including security and radio options. */
internal object SavedHotspotConfiguration {
    data class Snapshot(val value: Any, val ssid: String, val password: String)
    data class Start(val request: TetheringManager.TetheringRequest, val saved: Snapshot, val source: String)

    fun read(wifi: WifiManager): Snapshot {
        val config = wifi.javaClass.getMethod("getSoftApConfiguration").invoke(wifi)
            ?: error("System hotspot configuration is unavailable")
        val ssid = config.javaClass.getMethod("getSsid").invoke(config) as? String
            ?: error("System hotspot SSID is unavailable")
        check(ssid.isNotBlank()) { "System hotspot SSID is empty" }
        val password = config.javaClass.getMethod("getPassphrase").invoke(config) as? String ?: ""
        return Snapshot(config, ssid, password)
    }

    fun prepare(wifi: WifiManager, saved: Snapshot = read(wifi)): Start {
        val configType = Class.forName("android.net.wifi.SoftApConfiguration")
        var builder = TetheringManager.TetheringRequest.Builder(TetheringManager.TETHERING_WIFI)
        val setter = try {
            builder.javaClass.getMethod("setSoftApConfiguration", configType)
        } catch (_: NoSuchMethodException) {
            null
        }
        val explicitConfiguration = setter != null && runCatching {
            setter.invoke(builder, saved.value)
        }.isSuccess
        val source = if (explicitConfiguration) {
            "system_saved_explicit"
        } else {
            builder = TetheringManager.TetheringRequest.Builder(TetheringManager.TETHERING_WIFI)
            // The runtime may expose the request API but reject it behind a
            // feature or permission gate. Use the documented saved-config path.
            // Root may also expose the older WifiManager setter.
            val wifiSetter = runCatching {
                wifi.javaClass.getMethod("setSoftApConfiguration", configType)
            }.getOrNull()
            val reapplied = wifiSetter != null && runCatching {
                wifiSetter.invoke(wifi, saved.value) != false
            }.getOrDefault(false)
            if (reapplied) "system_saved_reapplied" else "system_saved_default"
        }
        return Start(builder.build(), saved, source)
    }

    fun encode(snapshot: Snapshot): String {
        val parcel = android.os.Parcel.obtain()
        return try {
            (snapshot.value as android.os.Parcelable).writeToParcel(parcel, 0)
            JSONObject().put("encodedConfig", Base64.encodeToString(parcel.marshall(), Base64.NO_WRAP)).toString()
        } finally { parcel.recycle() }
    }

    fun decode(line: String): Snapshot {
        val encoded = JSONObject(line).getString("encodedConfig")
        val bytes = Base64.decode(encoded, Base64.DEFAULT)
        val configType = Class.forName("android.net.wifi.SoftApConfiguration")
        val creator = configType.getField("CREATOR").get(null) as android.os.Parcelable.Creator<*>
        val parcel = android.os.Parcel.obtain()
        return try {
            parcel.unmarshall(bytes, 0, bytes.size)
            parcel.setDataPosition(0)
            val config = creator.createFromParcel(parcel) ?: error("Unable to restore saved hotspot config")
            val ssid = config.javaClass.getMethod("getSsid").invoke(config) as String
            val password = config.javaClass.getMethod("getPassphrase").invoke(config) as? String ?: ""
            check(ssid.isNotBlank()) { "System hotspot SSID is empty" }
            Snapshot(config, ssid, password)
        } finally { parcel.recycle() }
    }

    // This checks the persisted configuration; it is not a SoftApCallback report
    // of the live radio configuration. The explicit start request uses the snapshot.
    fun verifySaved(wifi: WifiManager, expected: Snapshot): Snapshot {
        val current = read(wifi)
        check(current.ssid == expected.ssid && current.password == expected.password) {
            "System hotspot configuration changed while starting; retry with current settings"
        }
        return current
    }
}
