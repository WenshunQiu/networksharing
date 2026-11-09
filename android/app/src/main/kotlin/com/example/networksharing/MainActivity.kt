package com.example.networksharing

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothDevice
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Android Back keeps the Activity/engine and foreground BLE session alive,
    // matching the desktop close-to-tray behavior. No notification action needs
    // to launch an Activity to execute a permitted hotspot operation.
    override fun popSystemNavigator(): Boolean {
        moveTaskToBack(true)
        return true
    }
    private lateinit var networkControl: NetworkControl
    private val channelName = "networksharing/bluetooth"
    private val permissionRequestCode = 4072
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingScanResult: MethodChannel.Result? = null
    private val scanPermissionRequestCode = 4073
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private val bondReceivers = mutableSetOf<android.content.BroadcastReceiver>()
    private val bondResults = mutableMapOf<String, MethodChannel.Result>()
    private val bondTimeouts = mutableMapOf<String, Runnable>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        networkControl = NetworkControl(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "inspect" -> inspectBluetooth(result)
                    "prepare" -> prepareBluetooth(result)
                    "pair" -> pairBluetooth(call.argument<String>("deviceId"), result)
                    "setBackgroundTransport" -> {
                        val enabled = call.argument<Boolean>("enabled") == true
                        if (enabled) {
                            startBleForegroundService(result)
                            return@setMethodCallHandler
                        } else stopService(android.content.Intent(this, BleForegroundService::class.java))
                        result.success(true)
                    }
                    "setWindowsCloseBehavior" -> result.success(false)
                    "openAppSettings" -> {
                        startActivity(android.content.Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.parse("package:$packageName")))
                        result.success(true)
                    }
                    "openBluetoothSettings" -> {
                        startActivity(android.content.Intent(android.provider.Settings.ACTION_BLUETOOTH_SETTINGS))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "networksharing/debug")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "selectWifi" -> {
                        startActivity(android.content.Intent(android.provider.Settings.ACTION_WIFI_SETTINGS))
                        result.success("已打开系统 Wi-Fi 设置，请选择网络并完成连接。")
                    }
                    "toggleHotspot", "startHotspot", "stopHotspot", "getHotspot" ->
                        networkControl.hotspot(if (call.method == "toggleHotspot") "startHotspot" else call.method, result)
                    "connectWifi" -> networkControl.connectWifi(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private var pendingServiceResult: MethodChannel.Result? = null
    private val notificationPermissionRequestCode = 4074

    private fun startBleForegroundService(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            if (pendingServiceResult != null) {
                result.error("busy", "A notification permission request is pending", null)
                return
            }
            pendingServiceResult = result
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), notificationPermissionRequestCode)
            return
        }
        try {
            val intent = android.content.Intent(this, BleForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
            android.util.Log.i("NetworkSharing", "foreground_service.start_requested")
            result.success(true)
        } catch (error: Exception) {
            android.util.Log.e("NetworkSharing", "foreground_service.start_failed", error)
            result.error("foreground_service_start_failed", error.javaClass.simpleName, null)
        }
    }

    @Suppress("MissingPermission")
    private fun pairBluetooth(deviceId: String?, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED
        ) {
            result.error("permission_denied", "Bluetooth connect permission is required", null)
            return
        }
        try {
            // The BLE plugin encodes a MAC address in the last 12 UUID digits.
            val node = deviceId?.takeIf { it.startsWith("00000000-0000-0000-0000-") }?.takeLast(12)
            val address = node?.chunked(2)?.joinToString(":")?.uppercase() ?: deviceId
            if (address == null || !BluetoothAdapter.checkBluetoothAddress(address)) {
                result.error("invalid_device_id", "Bluetooth device identifier is invalid", null)
                return
            }
            val device = (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager)
                .adapter?.getRemoteDevice(address)
            if (device == null) {
                result.error("device_not_found", "Bluetooth device is unavailable", null)
            } else if (device.bondState == BluetoothDevice.BOND_BONDED) {
                result.success(true)
            } else {
                if (bondResults.containsKey(device.address)) {
                    result.error("busy", "Pairing is already pending for this device", null)
                    return
                }
                val filter = android.content.IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
                val receiver = object : android.content.BroadcastReceiver() {
                    override fun onReceive(context: Context, intent: android.content.Intent) {
                        val changedDevice = if (Build.VERSION.SDK_INT >= 33) {
                            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                        } else {
                            @Suppress("DEPRECATION")
                            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                        }
                        if (changedDevice?.address != device.address) return
                        val state = intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.ERROR)
                        if (state == BluetoothDevice.BOND_BONDED || state == BluetoothDevice.BOND_NONE) {
                            unregisterReceiver(this)
                            bondReceivers.remove(this)
                            bondTimeouts.remove(device.address)?.let { mainHandler.removeCallbacks(it) }
                            bondResults.remove(device.address)?.success(state == BluetoothDevice.BOND_BONDED)
                        }
                    }
                }
                bondReceivers.add(receiver)
                bondResults[device.address] = result
                val timeout = Runnable {
                    if (bondResults.remove(device.address) != null) {
                        unregisterReceiver(receiver)
                        bondReceivers.remove(receiver)
                        bondTimeouts.remove(device.address)
                        result.error("pairing_timeout", "System Bluetooth pairing timed out", null)
                    }
                }
                bondTimeouts[device.address] = timeout
                mainHandler.postDelayed(timeout, 120_000)
                if (Build.VERSION.SDK_INT >= 33) registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
                else @Suppress("UnspecifiedRegisterReceiverFlag") registerReceiver(receiver, filter)
                if (!device.createBond()) {
                    unregisterReceiver(receiver)
                    bondReceivers.remove(receiver)
                    bondResults.remove(device.address)
                    bondTimeouts.remove(device.address)?.let { mainHandler.removeCallbacks(it) }
                    result.success(false)
                }
            }
        } catch (_: SecurityException) {
            result.error("permission_denied", "Bluetooth connect permission is required", null)
        } catch (_: IllegalArgumentException) {
            result.error("invalid_device_id", "Bluetooth device identifier is invalid", null)
        }
    }

    private fun prepareBluetooth(result: MethodChannel.Result) {
        if (pendingScanResult != null || pendingPermissionResult != null) {
            result.error("busy", "A Bluetooth permission request is pending", null)
            return
        }
        val required = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.BLUETOOTH_ADVERTISE)
        } else {
            arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION)
        }
        val missing = required.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isNotEmpty()) {
            pendingScanResult = result
            requestPermissions(missing.toTypedArray(), scanPermissionRequestCode)
        } else completePreparation(result)
    }

    private fun completePreparation(result: MethodChannel.Result) {
        val location = getSystemService(Context.LOCATION_SERVICE) as android.location.LocationManager
        val locationEnabled = if (Build.VERSION.SDK_INT >= 28) location.isLocationEnabled else
            location.isProviderEnabled(android.location.LocationManager.GPS_PROVIDER) ||
                location.isProviderEnabled(android.location.LocationManager.NETWORK_PROVIDER)
        result.success(mapOf("sdk" to Build.VERSION.SDK_INT,
            "locationRequired" to (Build.VERSION.SDK_INT <= 30),
            "locationEnabled" to locationEnabled))
    }

    private fun inspectBluetooth(result: MethodChannel.Result) {
        if (pendingPermissionResult != null || pendingScanResult != null) {
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
        if (networkControl.onPermissionsResult(requestCode, grantResults)) return
        if (requestCode == notificationPermissionRequestCode) {
            val result = pendingServiceResult ?: return
            pendingServiceResult = null
            if (Build.VERSION.SDK_INT < 33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
                startBleForegroundService(result)
            } else {
                result.error("notification_permission_denied", "Notifications permission is required to show the background connection", null)
            }
            return
        }
        if (requestCode == scanPermissionRequestCode) {
            val result = pendingScanResult ?: return
            pendingScanResult = null
            if (grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
                completePreparation(result)
            } else result.error("bluetooth_permission_denied", "Bluetooth permissions were denied", null)
            return
        }
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
        if (::networkControl.isInitialized) networkControl.dispose()
        pendingServiceResult?.error("activity_destroyed", "Service request interrupted", null)
        pendingServiceResult = null
        bondTimeouts.values.forEach { mainHandler.removeCallbacks(it) }
        bondTimeouts.clear()
        bondResults.values.forEach { it.error("activity_destroyed", "Pairing interrupted", null) }
        bondResults.clear()
        bondReceivers.forEach { runCatching { unregisterReceiver(it) } }
        bondReceivers.clear()
        pendingPermissionResult?.error("activity_destroyed", "Permission request interrupted", null)
        pendingPermissionResult = null
        pendingScanResult?.error("activity_destroyed", "Permission request interrupted", null)
        pendingScanResult = null
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (::networkControl.isInitialized) networkControl.onActivityResult(requestCode, resultCode, data)
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
