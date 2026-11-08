use serde::{Deserialize, Serialize};
use std::sync::{Mutex, OnceLock};
use uuid::Uuid;

const PROTOCOL_VERSION: u16 = 1;
const MAX_TRACKED_MESSAGES: usize = 4096;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum PairingMessageType {
    Hello,
    Challenge,
    Proof,
    Accepted,
    Rejected,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PairingEnvelope {
    pub version: u16,
    pub message_id: String,
    pub session_id: String,
    pub message_type: PairingMessageType,
    pub sent_at_unix_ms: u64,
    pub sequence: u64,
    pub payload_json: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum PairingSessionState {
    AwaitingPeer,
    Authenticating,
    Paired,
    Rejected,
    Expired,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PairingSession {
    pub session_id: String,
    pub pairing_code: String,
    pub expires_at_unix_ms: u64,
    pub state: PairingSessionState,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProtocolResult {
    pub accepted: bool,
    pub error_code: Option<String>,
}

mod replay {
use super::{PairingEnvelope, MAX_TRACKED_MESSAGES};
use std::collections::{HashSet, VecDeque};

pub(super) struct ReplayGuard {
    session_id: Option<String>,
    last_sequence: u64,
    seen: HashSet<String>,
    order: VecDeque<String>,
}

impl ReplayGuard {
    pub(super) fn new() -> Self {
        Self {
            session_id: None,
            last_sequence: 0,
            seen: HashSet::new(),
            order: VecDeque::new(),
        }
    }
}

impl ReplayGuard {
    pub(super) fn accept(&mut self, message: &PairingEnvelope) -> bool {
        if self.session_id.as_deref() != Some(&message.session_id) {
            self.session_id = Some(message.session_id.clone());
            self.last_sequence = 0;
            self.seen.clear();
            self.order.clear();
        }
        if message.sequence <= self.last_sequence || !self.seen.insert(message.message_id.clone()) {
            return false;
        }
        self.last_sequence = message.sequence;
        self.order.push_back(message.message_id.clone());
        if self.order.len() > MAX_TRACKED_MESSAGES {
            if let Some(expired) = self.order.pop_front() {
                self.seen.remove(&expired);
            }
        }
        true
    }
}
}

static REPLAY_GUARD: OnceLock<Mutex<replay::ReplayGuard>> = OnceLock::new();

fn unix_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

fn random_code() -> Result<String, String> {
    const ALPHABET: &[u8] = b"23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
    let mut bytes = [0_u8; 6];
    getrandom::getrandom(&mut bytes).map_err(|_| "secure_random_unavailable".to_string())?;
    Ok(bytes.iter().map(|byte| ALPHABET[(*byte as usize) % ALPHABET.len()] as char).collect())
}

pub fn create_pairing_session() -> Result<PairingSession, String> {
    Ok(PairingSession {
        session_id: Uuid::new_v4().to_string(),
        pairing_code: random_code()?,
        expires_at_unix_ms: unix_ms() + 5 * 60 * 1000,
        state: PairingSessionState::AwaitingPeer,
    })
}

pub fn create_pairing_envelope(
    session_id: String,
    message_type: PairingMessageType,
    sequence: u64,
    payload_json: String,
) -> PairingEnvelope {
    PairingEnvelope {
        version: PROTOCOL_VERSION,
        message_id: Uuid::new_v4().to_string(),
        session_id,
        message_type,
        sent_at_unix_ms: unix_ms(),
        sequence,
        payload_json,
    }
}

pub fn encode_pairing_envelope(message: PairingEnvelope) -> Result<String, String> {
    if message.version != PROTOCOL_VERSION {
        return Err("unsupported_protocol_version".into());
    }
    serde_json::to_string(&message).map_err(|_| "invalid_message".into())
}

pub fn decode_pairing_envelope(source: String) -> Result<PairingEnvelope, String> {
    let message: PairingEnvelope = serde_json::from_str(&source)
        .map_err(|_| "invalid_message".to_string())?;
    if message.version != PROTOCOL_VERSION {
        return Err("unsupported_protocol_version".into());
    }
    if message.session_id.is_empty() || message.message_id.is_empty() {
        return Err("invalid_message".into());
    }
    Ok(message)
}

pub fn accept_pairing_envelope(message: PairingEnvelope) -> ProtocolResult {
    let guard = REPLAY_GUARD.get_or_init(|| {
        Mutex::new(replay::ReplayGuard::new())
    });
    let accepted = guard
        .lock()
        .map(|mut state| state.accept(&message))
        .unwrap_or(false);
    if accepted {
        ProtocolResult { accepted: true, error_code: None }
    } else {
        ProtocolResult { accepted: false, error_code: Some("duplicate_or_stale_message".into()) }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn message(session: &str, sequence: u64) -> PairingEnvelope {
        create_pairing_envelope(session.into(), PairingMessageType::Hello, sequence, "{}".into())
    }

    #[test]
    fn creates_short_lived_random_pairing_code() {
        let one = create_pairing_session().unwrap();
        let two = create_pairing_session().unwrap();
        assert_eq!(one.pairing_code.len(), 6);
        assert!(one.pairing_code.bytes().all(|b| b"23456789ABCDEFGHJKLMNPQRSTUVWXYZ".contains(&b)));
        assert_ne!(one.session_id, two.session_id);
        assert!(one.expires_at_unix_ms > unix_ms());
    }

    #[test]
    fn envelope_round_trip_and_version_validation() {
        let encoded = encode_pairing_envelope(message("session", 1)).unwrap();
        let decoded = decode_pairing_envelope(encoded).unwrap();
        assert_eq!(decoded.session_id, "session");
        let mut incompatible = message("session", 2);
        incompatible.version = 99;
        assert_eq!(encode_pairing_envelope(incompatible).unwrap_err(), "unsupported_protocol_version");
    }

    #[test]
    fn replay_guard_rejects_duplicates_and_old_sequences() {
        let mut guard = replay::ReplayGuard::new();
        assert!(guard.accept(&message("a", 1)));
        assert!(!guard.accept(&message("a", 1)));
        assert!(!guard.accept(&message("a", 0)));
        assert!(guard.accept(&message("b", 1)));
    }
}
