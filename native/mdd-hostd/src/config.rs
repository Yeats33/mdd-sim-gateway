use std::{
    fs::{self, OpenOptions},
    io::Write,
    path::{Path, PathBuf},
};

use anyhow::{Context, bail};
use clap::Parser;
use rand::RngCore;

#[derive(Clone, Debug, Parser)]
#[command(name = "mdd-hostd", about = "MDD Apple Silicon VM/Docker supervisor")]
pub struct HostConfig {
    #[arg(long, env = "MDD_HOSTD_BIND", default_value = "127.0.0.1:48630")]
    pub bind: String,

    #[arg(long, env = "MDD_HOSTD_STATE_DIR", value_name = "DIR")]
    pub state_dir: Option<PathBuf>,

    #[arg(long, env = "MDD_SOURCE_DIR", value_name = "DIR")]
    pub source_dir: Option<PathBuf>,

    #[arg(long, env = "MDD_LIMA_TEMPLATE", value_name = "FILE")]
    pub lima_template: Option<PathBuf>,

    #[arg(long, env = "MDD_LIMA_BIN", default_value = "limactl")]
    pub limactl: PathBuf,

    #[arg(long, env = "MDD_VM_NAME", default_value = "mdd-sim-gateway")]
    pub vm_name: String,

    #[arg(long, env = "MDD_GATEWAY_PORT", default_value_t = 8443)]
    pub gateway_port: u16,
}

impl HostConfig {
    pub fn validated(mut self) -> anyhow::Result<Self> {
        if cfg!(target_os = "macos") && cfg!(not(target_arch = "aarch64")) {
            bail!("mdd-hostd supports Apple Silicon Macs only");
        }
        if self.vm_name.is_empty()
            || !self
                .vm_name
                .chars()
                .all(|ch| ch.is_ascii_alphanumeric() || ch == '-' || ch == '_')
        {
            bail!("VM name must contain only ASCII letters, digits, '-' or '_'");
        }
        self.state_dir = Some(match self.state_dir {
            Some(path) => absolutize(path)?,
            None => default_state_dir()?,
        });
        self.source_dir = Some(match self.source_dir {
            Some(path) => absolutize(path)?,
            None => std::env::current_dir().context("read current directory")?,
        });
        self.lima_template = Some(match self.lima_template {
            Some(path) => absolutize(path)?,
            None => PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("templates/mdd-vm.yaml"),
        });
        for path in [self.source_dir(), self.lima_template()] {
            if !path.exists() {
                bail!("required path does not exist: {}", path.display());
            }
        }
        Ok(self)
    }

    pub fn state_dir(&self) -> &Path {
        self.state_dir
            .as_deref()
            .expect("validated state directory")
    }

    pub fn source_dir(&self) -> &Path {
        self.source_dir
            .as_deref()
            .expect("validated source directory")
    }

    pub fn lima_template(&self) -> &Path {
        self.lima_template
            .as_deref()
            .expect("validated Lima template")
    }

    pub fn rendered_template(&self) -> PathBuf {
        self.state_dir().join("mdd-vm.yaml")
    }

    pub fn token_path(&self) -> PathBuf {
        self.state_dir().join("hostd.token")
    }

    pub fn ensure_state_dir(&self) -> anyhow::Result<()> {
        fs::create_dir_all(self.state_dir()).context("create host service state directory")?;
        set_owner_only_dir(self.state_dir())?;
        Ok(())
    }

    pub fn load_or_create_token(&self) -> anyhow::Result<String> {
        let path = self.token_path();
        if let Ok(value) = fs::read_to_string(&path) {
            let token = value.trim();
            if token.len() >= 32 {
                return Ok(token.to_owned());
            }
        }
        let mut bytes = [0_u8; 32];
        rand::rng().fill_bytes(&mut bytes);
        let token = hex::encode(bytes);
        let mut options = OpenOptions::new();
        options.write(true).create(true).truncate(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let mut file = options.open(&path).context("create host service token")?;
        writeln!(file, "{token}").context("write host service token")?;
        Ok(token)
    }
}

fn absolutize(path: PathBuf) -> anyhow::Result<PathBuf> {
    if path.is_absolute() {
        Ok(path)
    } else {
        Ok(std::env::current_dir()?.join(path))
    }
}

fn default_state_dir() -> anyhow::Result<PathBuf> {
    dirs::data_local_dir()
        .map(|dir| dir.join("MDD Sim Gateway"))
        .context("cannot determine the user application-support directory")
}

#[cfg(unix)]
fn set_owner_only_dir(path: &Path) -> anyhow::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(path, fs::Permissions::from_mode(0o700))?;
    Ok(())
}

#[cfg(not(unix))]
fn set_owner_only_dir(_path: &Path) -> anyhow::Result<()> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn config(root: &Path, name: &str) -> HostConfig {
        let source = root.join("source");
        let template = root.join("template.yaml");
        fs::create_dir_all(&source).unwrap();
        fs::write(&template, "vmType: vz\n").unwrap();
        HostConfig {
            bind: "127.0.0.1:48630".into(),
            state_dir: Some(root.join("state")),
            source_dir: Some(source),
            lima_template: Some(template),
            limactl: "limactl".into(),
            vm_name: name.into(),
            gateway_port: 8443,
        }
    }

    #[test]
    fn rejects_vm_names_that_could_become_options_or_shell_syntax() {
        let root = tempfile::tempdir().unwrap();
        assert!(config(root.path(), "mdd;echo").validated().is_err());
        assert!(config(root.path(), "mdd gateway").validated().is_err());
        assert!(config(root.path(), "mdd-gateway_1").validated().is_ok());
    }

    #[test]
    fn creates_and_reuses_an_owner_only_service_token() {
        let root = tempfile::tempdir().unwrap();
        let config = config(root.path(), "mdd").validated().unwrap();
        config.ensure_state_dir().unwrap();
        let first = config.load_or_create_token().unwrap();
        let second = config.load_or_create_token().unwrap();
        assert_eq!(first, second);
        assert_eq!(first.len(), 64);
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                fs::metadata(config.token_path())
                    .unwrap()
                    .permissions()
                    .mode()
                    & 0o777,
                0o600
            );
        }
    }
}
