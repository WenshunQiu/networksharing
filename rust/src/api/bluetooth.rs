/// System bonding is transport metadata, not application authentication.
#[derive(Debug, Clone)]
pub struct BluetoothPeer {
    pub id: String,
    pub name: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BluetoothAvailability {
    Ready,
    PoweredOff,
    Unavailable,
    PermissionDenied,
    Failed,
}

#[derive(Debug, Clone)]
pub struct BluetoothSnapshot {
    pub availability: BluetoothAvailability,
    pub devices: Vec<BluetoothPeer>,
}

#[derive(Debug, Clone)]
pub struct BluetoothScanResult {
    pub devices: Vec<BluetoothPeer>,
    pub error: Option<String>,
}

/// Migration probe only. Returned IDs are btleplug IDs and must not be passed
/// to the existing Flutter BLE plugin's connect method.
pub async fn probe_rust_bluetooth_scan(duration_ms: u32) -> BluetoothScanResult {
    #[cfg(target_os = "windows")]
    {
        windows_backend::scan(duration_ms).await.unwrap_or_else(|error| {
            BluetoothScanResult { devices: vec![], error: Some(error) }
        })
    }
    #[cfg(target_os = "android")]
    {
        BluetoothScanResult { devices: vec![], error: Some("android_btleplug_jni_init_required".into()) }
    }
    #[cfg(not(any(target_os = "windows", target_os = "android")))]
    {
        BluetoothScanResult { devices: vec![], error: Some("bluetooth_platform_unsupported".into()) }
    }
}

/// Runs on an FRB worker; does not change radio state or initiate pairing.
pub fn inspect_windows_bluetooth() -> BluetoothSnapshot {
    #[cfg(target_os = "windows")]
    {
        windows_backend::inspect().unwrap_or_else(|error| BluetoothSnapshot {
            availability: if error.code().0 == 0x80070005u32 as i32 {
                BluetoothAvailability::PermissionDenied
            } else {
                BluetoothAvailability::Failed
            },
            devices: vec![],
        })
    }
    #[cfg(not(target_os = "windows"))]
    {
        BluetoothSnapshot {
            availability: BluetoothAvailability::Unavailable,
            devices: vec![],
        }
    }
}

#[cfg(target_os = "windows")]
mod windows_backend {
    use super::*;
    use windows::Devices::Bluetooth::{BluetoothAdapter, BluetoothDevice};
    use windows::Devices::Enumeration::DeviceInformation;
    use windows::Devices::Radios::RadioState;
    use windows::Win32::System::WinRT::{RoInitialize, RoUninitialize, RO_INIT_MULTITHREADED};
    use btleplug::api::{Central, CentralEvent, Manager as _, Peripheral as _, ScanFilter};
    use futures::StreamExt;
    use std::time::Duration;

    struct Apartment;
    impl Drop for Apartment {
        fn drop(&mut self) {
            unsafe { RoUninitialize(); }
        }
    }

    pub(super) fn inspect() -> windows::core::Result<BluetoothSnapshot> {
        // Balance each successful initialization, including S_FALSE.
        unsafe { RoInitialize(RO_INIT_MULTITHREADED)?; }
        let _apartment = Apartment;
        let adapter = match BluetoothAdapter::GetDefaultAsync()?.get() {
            Ok(adapter) => adapter,
            Err(error) if error.code().0 == 0x80004003u32 as i32 => {
                return Ok(BluetoothSnapshot {
                    availability: BluetoothAvailability::Unavailable,
                    devices: vec![],
                });
            }
            Err(error) => return Err(error),
        };
        let radio = adapter.GetRadioAsync()?.get()?;
        let availability = if radio.State()? == RadioState::On {
            BluetoothAvailability::Ready
        } else {
            BluetoothAvailability::PoweredOff
        };
        if availability != BluetoothAvailability::Ready {
            return Ok(BluetoothSnapshot { availability, devices: vec![] });
        }
        let selector = BluetoothDevice::GetDeviceSelectorFromPairingState(true)?;
        let devices = DeviceInformation::FindAllAsyncAqsFilter(&selector)?.get()?;
        let mut peers = Vec::new();
        for device in devices {
            peers.push(BluetoothPeer {
                id: device.Id()?.to_string(),
                name: device.Name()?.to_string(),
            });
        }
        peers.sort_by(|a, b| a.name.cmp(&b.name).then(a.id.cmp(&b.id)));
        Ok(BluetoothSnapshot { availability, devices: peers })
    }

    pub(super) async fn scan(duration_ms: u32) -> Result<BluetoothScanResult, String> {
        static SCAN_LOCK: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());
        let _guard = SCAN_LOCK.try_lock().map_err(|_| "bluetooth_scan_busy".to_string())?;
        let manager = btleplug::platform::Manager::new().await.map_err(|e| e.to_string())?;
        let adapters = manager.adapters().await.map_err(|e| e.to_string())?;
        let adapter = adapters.into_iter().next().ok_or_else(|| "bluetooth_adapter_missing".to_string())?;
        let mut events = adapter.events().await.map_err(|e| e.to_string())?;
        adapter.start_scan(ScanFilter { services: vec![uuid::uuid!("77a10001-7a4b-4d31-9b22-7b8e12a45001")] }).await.map_err(|e| e.to_string())?;
        let deadline = tokio::time::sleep(Duration::from_millis(u64::from(duration_ms.min(60_000))));
        tokio::pin!(deadline);
        let mut found = std::collections::BTreeMap::new();
        loop {
            tokio::select! {
                _ = &mut deadline => break,
                event = events.next() => match event {
                    Some(CentralEvent::DeviceDiscovered(id)) | Some(CentralEvent::DeviceUpdated(id)) => {
                        if let Some(peripheral) = adapter.peripheral(&id).await.ok() {
                            if let Ok(Some(properties)) = peripheral.properties().await {
                                found.insert(id.to_string(), BluetoothPeer {
                                    id: id.to_string(),
                                    name: properties.local_name.unwrap_or_else(|| "Unnamed BLE device".into()),
                                });
                            }
                        }
                    },
                    Some(_) => {},
                    None => break,
                }
            }
        }
        adapter.stop_scan().await.map_err(|e| e.to_string())?;
        Ok(BluetoothScanResult { devices: found.into_values().collect(), error: None })
    }
}
