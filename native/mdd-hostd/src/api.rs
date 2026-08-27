use std::sync::Arc;

use axum::{
    Json, Router,
    extract::State,
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    routing::{get, post},
};
use serde::Serialize;
use subtle::ConstantTimeEq;
use uuid::Uuid;

use crate::supervisor::{OperationResult, Supervisor, SupervisorError};

struct AppState {
    supervisor: Arc<Supervisor>,
    token: String,
}

pub fn router(supervisor: Arc<Supervisor>, token: String) -> Router {
    let state = Arc::new(AppState { supervisor, token });
    Router::new()
        .route("/v1/health", get(health))
        .route("/v1/status", get(status))
        .route("/v1/install", post(install))
        .route("/v1/start", post(start))
        .route("/v1/stop", post(stop))
        .route("/v1/restart", post(restart))
        .route("/v1/reload", post(reload))
        .route("/v1/logs", get(logs))
        .route("/v1/pairing", post(pairing))
        .with_state(state)
}

#[derive(Serialize)]
struct Health {
    ok: bool,
    service: &'static str,
    protocol: u32,
}

async fn health() -> Json<Health> {
    Json(Health {
        ok: true,
        service: "mdd-hostd",
        protocol: 4,
    })
}

async fn status(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> Result<impl IntoResponse, ApiError> {
    authorize(&state, &headers)?;
    Ok(Json(state.supervisor.status().await))
}

macro_rules! operation {
    ($name:ident, $method:ident) => {
        async fn $name(
            State(state): State<Arc<AppState>>,
            headers: HeaderMap,
        ) -> Result<Json<OperationResult>, ApiError> {
            authorize(&state, &headers)?;
            Ok(Json(state.supervisor.$method().await?))
        }
    };
}

operation!(install, install);
operation!(start, start);
operation!(stop, stop);
operation!(restart, restart);
operation!(reload, reload);
operation!(logs, logs);

#[derive(Serialize)]
struct Pairing {
    qr: String,
    gateway_url: String,
    expires_in_seconds: u64,
}

async fn pairing(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> Result<Json<Pairing>, ApiError> {
    authorize(&state, &headers)?;
    let host = headers
        .get("x-mdd-lan-host")
        .and_then(|value| value.to_str().ok())
        .filter(|value| !value.contains(['\r', '\n']))
        .unwrap_or("mdd-gateway.local");
    let gateway_url = format!("https://{host}:{}", state.supervisor.config().gateway_port);
    let nonce = Uuid::new_v4();
    let qr = format!(
        "mdd://pair?url={}&nonce={nonce}",
        urlencoding::encode(&gateway_url)
    );
    Ok(Json(Pairing {
        qr,
        gateway_url,
        expires_in_seconds: 300,
    }))
}

fn authorize(state: &AppState, headers: &HeaderMap) -> Result<(), ApiError> {
    let supplied = headers
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.strip_prefix("Bearer "))
        .unwrap_or("");
    if supplied.as_bytes().ct_eq(state.token.as_bytes()).into() {
        Ok(())
    } else {
        Err(ApiError::Unauthorized)
    }
}

enum ApiError {
    Unauthorized,
    Supervisor(SupervisorError),
}

impl From<SupervisorError> for ApiError {
    fn from(value: SupervisorError) -> Self {
        Self::Supervisor(value)
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        match self {
            Self::Unauthorized => {
                (StatusCode::UNAUTHORIZED, "invalid host service token").into_response()
            }
            Self::Supervisor(error) => {
                (StatusCode::INTERNAL_SERVER_ERROR, error.to_string()).into_response()
            }
        }
    }
}
