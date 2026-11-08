package com.example.networksharing

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "networksharing/bluetooth"
    private val permissionRequestCode = 4072
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "inspect" -> inspectBluetooth(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun inspectBluetooth(result: MethodChannel.Result) {
        if (pendingPermissionResult != null) {
            result.error("busy", "A permission request is already pending", null)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingPermissionResult = result
            requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), permissionRequestCode)
            return
        }
        completeSnapshot(result)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permissionRequestCode) return
        val result = pendingPermissionResult ?: return
        pendingPermissionResult = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            completeSnapshot(result)
        } else {
            result.success(mapOf("state" to "permissionDenied", "devices" to emptyList<Map<String, String>>()))
        }
    }

    private fun completeSnapshot(result: MethodChannel.Result) {
        try {
            result.success(readBluetoothSnapshot())
        } catch (_: SecurityException) {
            result.success(mapOf("state" to "permissionDenied", "devices" to emptyList<Map<String, String>>()))
        } catch (_: Exception) {
            result.error("bluetooth_unavailable", "Unable to query Bluetooth state", null)
        }
    }

    override fun onDestroy() {
        pendingPermissionResult?.error("activity_destroyed", "Permission request interrupted", null)
        pendingPermissionResult = null
        super.onDestroy()
    }

    @Suppress("MissingPermission")
    private fun readBluetoothSnapshot(): Map<String, Any> {
        val manager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        val adapter: BluetoothAdapter? = manager?.adapter
        if (adapter == null) return mapOf("state" to "unavailable", "devices" to emptyList<Map<String, String>>())
        val state = when {
            !adapter.isEnabled -> "poweredOff"
            else -> "ready"
        }
        val devices = if (state == "ready") {
            adapter.bondedDevices.map { device ->
                mapOf("id" to device.address, "name" to (device.name ?: "Bluetooth device"))
            }.sortedBy { it["name"] }
        } else emptyList()
        return mapOf("state" to state, "devices" to devices)
    }
}
