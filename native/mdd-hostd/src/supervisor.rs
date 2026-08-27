use std::{fs, path::Path, sync::Arc};

use serde::Serialize;
use thiserror::Error;
use tokio::{net::TcpStream, sync::Mutex};

use crate::{config::HostConfig, process::CommandRunner};

#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum VmState {
    NotInstalled,
    Stopped,
    Running,
    Broken,
}

#[derive(Clone, Debug, Serialize)]
pub struct HostStatus {
    pub vm: VmState,
    pub gateway_ready: bool,
    pub gateway_url: String,
    pub vm_name: String,
}

#[derive(Clone, Debug, Serialize)]
pub struct OperationResult {
    pub ok: bool,
    pub operation: String,
    pub detail: String,
}

#[derive(Debug, Error)]
pub enum SupervisorError {
    #[error("cannot run {program}: {source}")]
    Spawn {
        program: String,
        #[source]
        source: std::io::Error,
    },
    #[error("{operation} failed: {detail}")]
    Command { operation: String, detail: String },
    #[error("cannot prepare VM template: {0}")]
    Template(#[from] std::io::Error),
}

pub struct Supervisor {
    config: HostConfig,
    runner: Arc<dyn CommandRunner>,
    operation_lock: Mutex<()>,
}

impl Supervisor {
    pub fn new(config: HostConfig, runner: Arc<dyn CommandRunner>) -> Self {
        Self {
            config,
            runner,
            operation_lock: Mutex::new(()),
        }
    }

    pub fn config(&self) -> &HostConfig {
        &self.config
    }

    pub async fn status(&self) -> HostStatus {
        let vm = self.vm_state().await;
        let gateway_ready = vm == VmState::Running && self.gateway_ready().await;
        HostStatus {
            vm,
            gateway_ready,
            gateway_url: format!("https://127.0.0.1:{}", self.config.gateway_port),
            vm_name: self.config.vm_name.clone(),
        }
    }

    pub async fn install(&self) -> Result<OperationResult, SupervisorError> {
        let _guard = self.operation_lock.lock().await;
        self.ensure_created().await?;
        if self.vm_state().await != VmState::Running {
            self.run_lima(
                "start VM",
                vec!["start".into(), self.config.vm_name.clone()],
            )
            .await?;
        }
        self.guest_install("install gateway", "install").await?;
        Ok(OperationResult {
            ok: true,
            operation: "install".into(),
            detail: "Linux VM and gateway installation completed".into(),
        })
    }

    pub async fn validate_template(&self) -> Result<(), SupervisorError> {
        let _guard = self.operation_lock.lock().await;
        self.render_template()?;
        self.run_lima(
            "validate VM template",
            vec![
                "template".into(),
                "validate".into(),
                self.config.rendered_template().display().to_string(),
            ],
        )
        .await?;
        Ok(())
    }

    pub async fn start(&self) -> Result<OperationResult, SupervisorError> {
        let _guard = self.operation_lock.lock().await;
        self.ensure_created().await?;
        self.run_lima(
            "start VM",
            vec!["start".into(), self.config.vm_name.clone()],
        )
        .await?;
        Ok(OperationResult {
            ok: true,
            operation: "start".into(),
            detail: "VM started".into(),
        })
    }

    pub async fn stop(&self) -> Result<OperationResult, SupervisorError> {
        let _guard = self.operation_lock.lock().await;
        self.run_lima("stop VM", vec!["stop".into(), self.config.vm_name.clone()])
            .await?;
        Ok(OperationResult {
            ok: true,
            operation: "stop".into(),
            detail: "VM stopped".into(),
        })
    }

    pub async fn restart(&self) -> Result<OperationResult, SupervisorError> {
        let _guard = self.operation_lock.lock().await;
        self.run_lima("stop VM", vec!["stop".into(), self.config.vm_name.clone()])
            .await?;
        self.run_lima(
            "start VM",
            vec!["start".into(), self.config.vm_name.clone()],
        )
        .await?;
        Ok(OperationResult {
            ok: true,
            operation: "restart".into(),
            detail: "VM restarted".into(),
        })
    }

    pub async fn reload(&self) -> Result<OperationResult, SupervisorError> {
        let _guard = self.operation_lock.lock().await;
        self.guest_install("reload gateway", "reload").await?;
        Ok(OperationResult {
            ok: true,
            operation: "reload".into(),
            detail: "Gateway services reloaded".into(),
        })
    }

    pub async fn logs(&self) -> Result<OperationResult, SupervisorError> {
        let output = self
            .run_lima(
                "read gateway logs",
                self.guest_args(vec![
                    "sudo".into(),
                    "/mnt/mdd-source/install.sh".into(),
                    "logs".into(),
                    "--no-follow".into(),
                ]),
            )
            .await?;
        Ok(OperationResult {
            ok: true,
            operation: "logs".into(),
            detail: output,
        })
    }

    async fn vm_state(&self) -> VmState {
        let result = self
            .runner
            .run(
                &self.config.limactl,
                &[
                    "list".into(),
                    self.config.vm_name.clone(),
                    "--format".into(),
                    "{{.Status}}".into(),
                ],
            )
            .await;
        match result {
            Err(_) => VmState::Broken,
            Ok(output) if !output.success() || output.stdout.is_empty() => VmState::NotInstalled,
            Ok(output) if output.stdout.to_ascii_lowercase().contains("running") => {
                VmState::Running
            }
            Ok(_) => VmState::Stopped,
        }
    }

    async fn gateway_ready(&self) -> bool {
        tokio::time::timeout(
            std::time::Duration::from_secs(3),
            TcpStream::connect((std::net::Ipv4Addr::LOCALHOST, self.config.gateway_port)),
        )
        .await
        .is_ok_and(|result| result.is_ok())
    }

    async fn ensure_created(&self) -> Result<(), SupervisorError> {
        if self.vm_state().await != VmState::NotInstalled {
            return Ok(());
        }
        self.render_template()?;
        self.run_lima(
            "create VM",
            vec![
                "create".into(),
                "--name".into(),
                self.config.vm_name.clone(),
                self.config.rendered_template().display().to_string(),
            ],
        )
        .await?;
        Ok(())
    }

    fn render_template(&self) -> Result<(), SupervisorError> {
        let template = fs::read_to_string(self.config.lima_template())?;
        let source = yaml_string(self.config.source_dir());
        let rendered = template.replace("__MDD_SOURCE__", &source);
        fs::write(self.config.rendered_template(), rendered)?;
        Ok(())
    }

    async fn guest_install(
        &self,
        operation: &str,
        action: &str,
    ) -> Result<String, SupervisorError> {
        self.run_lima(
            operation,
            self.guest_args(vec![
                "sudo".into(),
                "env".into(),
                "MDD_DATA_DIR=/var/lib/mdd-sim-gateway".into(),
                "/mnt/mdd-source/install.sh".into(),
                action.into(),
            ]),
        )
        .await
    }

    fn guest_args(&self, command: Vec<String>) -> Vec<String> {
        let mut args = vec!["shell".into(), self.config.vm_name.clone(), "--".into()];
        args.extend(command);
        args
    }

    async fn run_lima(
        &self,
        operation: &str,
        args: Vec<String>,
    ) -> Result<String, SupervisorError> {
        let output = self
            .runner
            .run(&self.config.limactl, &args)
            .await
            .map_err(|source| SupervisorError::Spawn {
                program: self.config.limactl.display().to_string(),
                source,
            })?;
        if !output.success() {
            return Err(SupervisorError::Command {
                operation: operation.to_owned(),
                detail: if output.stderr.is_empty() {
                    output.stdout
                } else {
                    output.stderr
                },
            });
        }
        Ok(if output.stdout.is_empty() {
            operation.to_owned()
        } else {
            output.stdout
        })
    }
}

fn yaml_string(path: &Path) -> String {
    let value = path.display().to_string();
    format!(
        "\"{}\"",
        value
            .replace('\\', "\\\\")
            .replace('"', "\\\"")
            .replace('\n', "")
    )
}

#[cfg(test)]
mod tests {
    use std::{
        collections::VecDeque,
        path::PathBuf,
        process::ExitStatus,
        sync::{Arc, Mutex},
    };

    use async_trait::async_trait;

    use super::*;
    use crate::process::ProcessOutput;

    #[cfg(unix)]
    fn status(code: i32) -> ExitStatus {
        use std::os::unix::process::ExitStatusExt;
        ExitStatus::from_raw(code << 8)
    }

    struct MockRunner {
        outputs: Mutex<VecDeque<ProcessOutput>>,
        calls: Mutex<Vec<Vec<String>>>,
    }

    impl MockRunner {
        fn new(outputs: Vec<ProcessOutput>) -> Self {
            Self {
                outputs: Mutex::new(outputs.into()),
                calls: Mutex::new(Vec::new()),
            }
        }
    }

    #[async_trait]
    impl CommandRunner for MockRunner {
        async fn run(&self, program: &Path, args: &[String]) -> std::io::Result<ProcessOutput> {
            self.calls.lock().unwrap().push(
                std::iter::once(program.display().to_string())
                    .chain(args.iter().cloned())
                    .collect(),
            );
            Ok(self.outputs.lock().unwrap().pop_front().unwrap())
        }
    }

    fn output(code: i32, stdout: &str) -> ProcessOutput {
        ProcessOutput {
            status: status(code),
            stdout: stdout.into(),
            stderr: String::new(),
        }
    }

    fn config(root: &Path) -> HostConfig {
        let source = root.join("source with spaces");
        let template = root.join("template.yaml");
        fs::create_dir_all(&source).unwrap();
        fs::write(&template, "images: []\nmount: __MDD_SOURCE__\n").unwrap();
        HostConfig {
            bind: "127.0.0.1:48630".into(),
            state_dir: Some(root.join("state")),
            source_dir: Some(source),
            lima_template: Some(template),
            limactl: PathBuf::from("limactl-test"),
            vm_name: "mdd-test".into(),
            gateway_port: 8443,
            validate_template_only: false,
        }
        .validated()
        .unwrap()
    }

    #[tokio::test]
    async fn creates_then_starts_the_vm_without_a_shell() {
        let root = tempfile::tempdir().unwrap();
        let config = config(root.path());
        config.ensure_state_dir().unwrap();
        let runner = Arc::new(MockRunner::new(vec![
            output(1, ""),
            output(0, "created"),
            output(0, "started"),
        ]));
        let supervisor = Supervisor::new(config.clone(), runner.clone());

        let result = supervisor.start().await.unwrap();

        assert!(result.ok);
        let calls = runner.calls.lock().unwrap();
        assert_eq!(calls.len(), 3);
        assert_eq!(calls[1][1], "create");
        assert_eq!(calls[2][1], "start");
        assert!(
            calls
                .iter()
                .flatten()
                .all(|argument| argument != "sh" && argument != "bash")
        );
        let rendered = fs::read_to_string(config.rendered_template()).unwrap();
        assert!(rendered.contains("\""));
        assert!(rendered.contains("source with spaces"));
        assert!(!rendered.contains("__MDD_SOURCE__"));
    }

    #[tokio::test]
    async fn validates_the_fully_rendered_vm_template() {
        let root = tempfile::tempdir().unwrap();
        let config = config(root.path());
        config.ensure_state_dir().unwrap();
        let runner = Arc::new(MockRunner::new(vec![output(0, "validated")]));
        let supervisor = Supervisor::new(config.clone(), runner.clone());

        supervisor.validate_template().await.unwrap();

        let calls = runner.calls.lock().unwrap();
        assert_eq!(calls.len(), 1);
        assert_eq!(calls[0][1], "template");
        assert_eq!(calls[0][2], "validate");
        assert_eq!(
            calls[0][3],
            config.rendered_template().display().to_string()
        );
        let rendered = fs::read_to_string(config.rendered_template()).unwrap();
        assert!(!rendered.contains("__MDD_SOURCE__"));
    }

    #[tokio::test]
    async fn installs_gateway_without_restarting_an_already_running_vm() {
        let root = tempfile::tempdir().unwrap();
        let config = config(root.path());
        config.ensure_state_dir().unwrap();
        let runner = Arc::new(MockRunner::new(vec![
            output(0, "Running"),
            output(0, "Running"),
            output(0, "install complete"),
        ]));
        let supervisor = Supervisor::new(config, runner.clone());

        let result = supervisor.install().await.unwrap();

        assert!(result.ok);
        let calls = runner.calls.lock().unwrap();
        assert_eq!(calls.len(), 3);
        assert!(
            calls
                .iter()
                .all(|call| !call.iter().any(|arg| arg == "start"))
        );
        assert_eq!(calls[2][1], "shell");
        assert!(calls[2].iter().any(|arg| arg == "install"));
    }

    #[tokio::test]
    async fn reads_a_bounded_gateway_log_snapshot() {
        let root = tempfile::tempdir().unwrap();
        let config = config(root.path());
        let runner = Arc::new(MockRunner::new(vec![output(0, "recent logs")]));
        let supervisor = Supervisor::new(config, runner.clone());

        let result = supervisor.logs().await.unwrap();

        assert_eq!(result.detail, "recent logs");
        let calls = runner.calls.lock().unwrap();
        assert_eq!(calls.len(), 1);
        assert!(calls[0].iter().any(|arg| arg == "logs"));
        assert!(calls[0].iter().any(|arg| arg == "--no-follow"));
    }
}
