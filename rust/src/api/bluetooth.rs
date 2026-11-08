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
}
