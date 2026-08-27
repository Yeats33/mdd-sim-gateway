use std::{net::SocketAddr, sync::Arc};

use anyhow::Context;
use clap::Parser;
use mdd_hostd::{api, config::HostConfig, process::ProcessRunner, supervisor::Supervisor};
use tracing::info;
#[cfg(target_os = "macos")]
use tracing::warn;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "mdd_hostd=info".into()),
        )
        .init();

    let config = HostConfig::parse().validated()?;
    let validate_template_only = config.validate_template_only;
    config.ensure_state_dir()?;
    let token = config.load_or_create_token()?;
    let bind: SocketAddr = config.bind.parse().context("invalid --bind address")?;
    let supervisor = Arc::new(Supervisor::new(config, Arc::new(ProcessRunner)));
    if validate_template_only {
        supervisor.validate_template().await?;
        info!("MDD Lima VM template validated");
        return Ok(());
    }
    #[cfg(target_os = "macos")]
    let _pcsc_bridge = mdd_hostd::pcsc_bridge::spawn().context("start Mac PC/SC bridge")?;
    #[cfg(target_os = "macos")]
    {
        let supervisor = Arc::clone(&supervisor);
        tokio::spawn(async move {
            let mut last_error = String::new();
            for attempt in 0..60 {
                match supervisor.reconcile_pcsc_bridge().await {
                    Ok(_) => {
                        info!("Mac PC/SC bridge configured in Linux VM");
                        return;
                    }
                    Err(error) => {
                        let current = error.to_string();
                        if current != last_error {
                            info!(reason = %current, "Mac PC/SC guest bridge waiting");
                            last_error = current;
                        }
                    }
                }
                tokio::time::sleep(std::time::Duration::from_secs(5)).await;
                if attempt == 59 {
                    warn!(reason = %last_error, "Mac PC/SC guest bridge was not configured");
                }
            }
        });
    }
    let app = api::router(supervisor, token);
    let listener = tokio::net::TcpListener::bind(bind).await?;
    info!(%bind, "MDD Mac host service listening");
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await?;
    Ok(())
}

async fn shutdown_signal() {
    let ctrl_c = async {
        tokio::signal::ctrl_c()
            .await
            .expect("install Ctrl-C handler");
    };
    #[cfg(unix)]
    let terminate = async {
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
            .expect("install SIGTERM handler")
            .recv()
            .await;
    };
    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();
    tokio::select! { _ = ctrl_c => {}, _ = terminate => {} }
}
