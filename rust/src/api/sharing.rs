use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum ShareDirection {
    PhoneProvides,
    ComputerProvides,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum ShareSessionState {
    AwaitingApproval,
    PreparingProvider,
    CredentialsReady,
    JoiningNetwork,
    VerifyingNetwork,
    Active,
    IdleClosing,
    Closed,
    Rejected,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ShareSession {
    pub session_id: String,
    pub requester_device_id: String,
    pub provider_device_id: String,
    pub direction: ShareDirection,
    pub state: ShareSessionState,
    pub revision: u64,
    pub last_error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ShareTransitionResult {
    pub accepted: bool,
    pub error_code: Option<String>,
    pub session: Option<ShareSession>,
}

static SESSIONS: OnceLock<Mutex<HashMap<String, ShareSession>>> = OnceLock::new();

fn sessions() -> &'static Mutex<HashMap<String, ShareSession>> {
    SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn transition_allowed(from: &ShareSessionState, to: &ShareSessionState) -> bool {
    use ShareSessionState::*;
    matches!(
        (from, to),
        (AwaitingApproval, PreparingProvider | Rejected | Failed)
            | (PreparingProvider, CredentialsReady | Failed | Closed)
            | (CredentialsReady, JoiningNetwork | Failed | Closed)
            | (JoiningNetwork, VerifyingNetwork | Failed | Closed)
            | (VerifyingNetwork, Active | Failed | Closed)
            | (Active, IdleClosing | Failed | Closed)
            | (IdleClosing, Active | Closed | Failed)
    )
}

fn result(session: Option<ShareSession>, error_code: Option<&str>) -> ShareTransitionResult {
    ShareTransitionResult {
        accepted: session.is_some(),
        session,
        error_code: error_code.map(str::to_owned),
    }
}

pub fn request_share(
    requester_device_id: String,
    provider_device_id: String,
    direction: ShareDirection,
) -> Result<ShareSession, String> {
    if requester_device_id.is_empty() || provider_device_id.is_empty() {
        return Err("device_id_required".into());
    }
    if requester_device_id == provider_device_id {
        return Err("same_device_not_allowed".into());
    }
    let mut registry = sessions().lock().map_err(|_| "session_registry_unavailable")?;
    if registry.values().any(|session| {
        session.state != ShareSessionState::Closed
            && session.state != ShareSessionState::Rejected
            && session.state != ShareSessionState::Failed
            && (session.requester_device_id == requester_device_id
                || session.provider_device_id == requester_device_id
                || session.requester_device_id == provider_device_id
                || session.provider_device_id == provider_device_id)
    }) {
        return Err("device_already_in_active_session".into());
    }
    let session = ShareSession {
        session_id: Uuid::new_v4().to_string(),
        requester_device_id,
        provider_device_id,
        direction,
        state: ShareSessionState::AwaitingApproval,
        revision: 0,
        last_error: None,
    };
    registry.insert(session.session_id.clone(), session.clone());
    Ok(session)
}

pub fn get_share_session(session_id: String) -> Option<ShareSession> {
    sessions().lock().ok()?.get(&session_id).cloned()
}

pub fn transition_share_session(
    session_id: String,
    expected_revision: u64,
    next_state: ShareSessionState,
    error_code: Option<String>,
) -> ShareTransitionResult {
    let Ok(mut registry) = sessions().lock() else {
        return result(None, Some("session_registry_unavailable"));
    };
    let Some(session) = registry.get_mut(&session_id) else {
        return result(None, Some("session_not_found"));
    };
    if session.revision != expected_revision {
        return result(None, Some("stale_session_revision"));
    }
    if !transition_allowed(&session.state, &next_state) {
        return result(None, Some("invalid_state_transition"));
    }
    if next_state == ShareSessionState::Failed && error_code.as_deref().unwrap_or("").is_empty() {
        return result(None, Some("failure_reason_required"));
    }
    session.state = next_state;
    session.revision += 1;
    session.last_error = error_code;
    result(Some(session.clone()), None)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn requires_approval_and_network_verification_before_active() {
        let session = request_share(
            Uuid::new_v4().to_string(),
            Uuid::new_v4().to_string(),
            ShareDirection::PhoneProvides,
        )
        .unwrap();
        let skipped = transition_share_session(
            session.session_id.clone(), 0, ShareSessionState::Active, None,
        );
        assert_eq!(skipped.error_code.as_deref(), Some("invalid_state_transition"));
        let mut current = session;
        for next in [
            ShareSessionState::PreparingProvider,
            ShareSessionState::CredentialsReady,
            ShareSessionState::JoiningNetwork,
            ShareSessionState::VerifyingNetwork,
            ShareSessionState::Active,
        ] {
            current = transition_share_session(
                current.session_id.clone(), current.revision, next, None,
            )
            .session
            .unwrap();
        }
        assert_eq!(current.state, ShareSessionState::Active);
    }

    #[test]
    fn rejects_device_conflicts_and_stale_updates() {
        let requester = Uuid::new_v4().to_string();
        let provider = Uuid::new_v4().to_string();
        let session = request_share(
            requester.clone(), provider.clone(), ShareDirection::ComputerProvides,
        )
        .unwrap();
        assert_eq!(
            request_share(requester.clone(), Uuid::new_v4().to_string(), ShareDirection::PhoneProvides)
                .unwrap_err(),
            "device_already_in_active_session"
        );
        let moved = transition_share_session(
            session.session_id.clone(), 0, ShareSessionState::PreparingProvider, None,
        );
        assert!(moved.accepted);
        let stale = transition_share_session(
            session.session_id, 0, ShareSessionState::Rejected, None,
        );
        assert_eq!(stale.error_code.as_deref(), Some("stale_session_revision"));
    }
}
