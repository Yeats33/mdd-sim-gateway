use std::{path::Path, process::ExitStatus};

use async_trait::async_trait;
use tokio::process::Command;

#[derive(Debug)]
pub struct ProcessOutput {
    pub status: ExitStatus,
    pub stdout: String,
    pub stderr: String,
}

impl ProcessOutput {
    pub fn success(&self) -> bool {
        self.status.success()
    }
}

#[async_trait]
pub trait CommandRunner: Send + Sync {
    async fn run(&self, program: &Path, args: &[String]) -> std::io::Result<ProcessOutput>;
}

pub struct ProcessRunner;

#[async_trait]
impl CommandRunner for ProcessRunner {
    async fn run(&self, program: &Path, args: &[String]) -> std::io::Result<ProcessOutput> {
        let output = Command::new(program)
            .args(args)
            .kill_on_drop(true)
            .output()
            .await?;
        Ok(ProcessOutput {
            status: output.status,
            stdout: String::from_utf8_lossy(&output.stdout).trim().to_owned(),
            stderr: String::from_utf8_lossy(&output.stderr).trim().to_owned(),
        })
    }
}
