#[cfg(any(target_os = "macos", test))]
use std::io::{self, Read, Write};
#[cfg(any(target_os = "macos", test))]
use std::{ffi::OsString, path::Path};

#[cfg(any(target_os = "macos", test))]
const MAX_VPCD_FRAME: usize = u16::MAX as usize;
pub const MAC_PCSC_BRIDGE_PORT: u16 = 0x7f00;

#[cfg(any(target_os = "macos", test))]
pub fn ssh_forward_args(ssh_config: &Path, vm_name: &str) -> Vec<OsString> {
    vec![
        "-F".into(),
        ssh_config.as_os_str().to_owned(),
        "-o".into(),
        "BatchMode=yes".into(),
        "-o".into(),
        "ExitOnForwardFailure=yes".into(),
        "-o".into(),
        "ServerAliveInterval=15".into(),
        "-o".into(),
        "ServerAliveCountMax=3".into(),
        "-N".into(),
        "-L".into(),
        format!("127.0.0.1:{0}:127.0.0.1:{0}", MAC_PCSC_BRIDGE_PORT).into(),
        format!("lima-{vm_name}").into(),
    ]
}

#[cfg(any(target_os = "macos", test))]
fn read_frame(reader: &mut impl Read) -> io::Result<Vec<u8>> {
    let mut header = [0_u8; 2];
    reader.read_exact(&mut header)?;
    let length = u16::from_be_bytes(header) as usize;
    let mut payload = vec![0_u8; length];
    reader.read_exact(&mut payload)?;
    Ok(payload)
}

#[cfg(any(target_os = "macos", test))]
fn write_frame(writer: &mut impl Write, payload: &[u8]) -> io::Result<()> {
    let length = u16::try_from(payload.len()).map_err(|_| {
        io::Error::new(
            io::ErrorKind::InvalidData,
            format!("VPCD frame exceeds {MAX_VPCD_FRAME} bytes"),
        )
    })?;
    writer.write_all(&length.to_be_bytes())?;
    writer.write_all(payload)?;
    writer.flush()
}

#[cfg(target_os = "macos")]
mod macos {
    use std::{
        io,
        net::{Ipv4Addr, SocketAddr, SocketAddrV4, TcpStream},
        thread,
        time::Duration,
    };

    use anyhow::{Context as _, bail};
    use pcsc::{
        Context as PcscContext, Disposition, Error as PcscError, Protocols, Scope, ShareMode,
    };
    use tracing::info;

    use super::{read_frame, write_frame};

    const VPCD_CONTROL_OFF: u8 = 0x00;
    const VPCD_CONTROL_ON: u8 = 0x01;
    const VPCD_CONTROL_RESET: u8 = 0x02;
    const VPCD_CONTROL_ATR: u8 = 0x04;
    use super::MAC_PCSC_BRIDGE_PORT;

    pub fn spawn() -> io::Result<thread::JoinHandle<()>> {
        thread::Builder::new()
            .name("mdd-mac-pcsc".into())
            .spawn(move || {
                let mut previous = String::new();
                loop {
                    if let Err(error) = relay_once() {
                        let current = error.to_string();
                        if current != previous {
                            info!(reason = %current, "Mac PC/SC bridge waiting");
                            previous = current;
                        }
                    }
                    thread::sleep(Duration::from_secs(2));
                }
            })
    }

    fn relay_once() -> anyhow::Result<()> {
        let context = PcscContext::establish(Scope::User).context("PC/SC is unavailable")?;
        let readers = match context.list_readers_owned() {
            Ok(readers) => readers,
            Err(PcscError::NoReadersAvailable) => bail!("no Mac PC/SC reader is connected"),
            Err(error) => return Err(error).context("list Mac PC/SC readers"),
        };
        for reader in readers {
            let mut card = match context.connect(&reader, ShareMode::Shared, Protocols::ANY) {
                Ok(card) => card,
                Err(PcscError::NoSmartcard | PcscError::RemovedCard) => continue,
                Err(PcscError::ReaderUnavailable) => continue,
                Err(error) => return Err(error).context("connect to Mac smart card"),
            };
            let transaction = card.transaction().context("lock Mac smart card")?;
            let atr = transaction
                .status2_owned()
                .context("read Mac smart-card status")?
                .atr()
                .to_vec();
            if atr.is_empty() {
                bail!("inserted Mac smart card returned an empty ATR");
            }
            let address =
                SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::LOCALHOST, MAC_PCSC_BRIDGE_PORT));
            let stream = TcpStream::connect_timeout(&address, Duration::from_secs(2))
                .context("Linux VM PC/SC bridge is not ready")?;
            stream.set_nodelay(true)?;
            info!("Mac PC/SC card connected to Linux VM bridge");
            return relay_session(transaction, stream, &atr);
        }
        bail!("no smart card is inserted in a Mac PC/SC reader")
    }

    fn relay_session(
        mut transaction: pcsc::Transaction<'_>,
        mut stream: TcpStream,
        atr: &[u8],
    ) -> anyhow::Result<()> {
        loop {
            let payload = read_frame(&mut stream).context("read VPCD request")?;
            if payload.len() == 1 {
                match payload[0] {
                    VPCD_CONTROL_ATR => write_frame(&mut stream, atr)?,
                    VPCD_CONTROL_ON | VPCD_CONTROL_RESET => transaction
                        .reconnect(ShareMode::Shared, Protocols::ANY, Disposition::ResetCard)
                        .context("reset Mac smart card")?,
                    VPCD_CONTROL_OFF => {}
                    _ => bail!("unsupported VPCD control request"),
                }
                continue;
            }
            if payload.is_empty() {
                continue;
            }
            let mut response = vec![0_u8; pcsc::MAX_BUFFER_SIZE_EXTENDED];
            let response_length = transaction
                .transmit(&payload, &mut response)
                .context("transmit Mac smart-card APDU")?
                .len();
            response.truncate(response_length);
            write_frame(&mut stream, &response)?;
        }
    }
}

#[cfg(target_os = "macos")]
pub use macos::spawn;

#[cfg(test)]
mod tests {
    use std::io::Cursor;

    use super::*;

    #[test]
    fn vpcd_frames_use_a_big_endian_u16_length() {
        let mut encoded = Vec::new();
        write_frame(&mut encoded, &[0x00, 0xa4, 0x04]).unwrap();
        assert_eq!(encoded, [0x00, 0x03, 0x00, 0xa4, 0x04]);
        assert_eq!(
            read_frame(&mut Cursor::new(encoded)).unwrap(),
            [0x00, 0xa4, 0x04]
        );
    }

    #[test]
    fn oversized_vpcd_frames_are_rejected() {
        let mut encoded = Vec::new();
        let payload = vec![0_u8; MAX_VPCD_FRAME + 1];
        assert_eq!(
            write_frame(&mut encoded, &payload).unwrap_err().kind(),
            io::ErrorKind::InvalidData
        );
    }

    #[test]
    fn ssh_forward_is_loopback_only_and_uses_lima_config() {
        let args = ssh_forward_args(Path::new("/tmp/ssh.config"), "mdd-sim-gateway");
        let rendered = args
            .iter()
            .map(|value| value.to_string_lossy())
            .collect::<Vec<_>>();
        assert!(rendered.iter().any(|value| value == "/tmp/ssh.config"));
        assert!(
            rendered
                .iter()
                .any(|value| value == "127.0.0.1:32512:127.0.0.1:32512")
        );
        assert_eq!(rendered.last().unwrap(), "lima-mdd-sim-gateway");
    }
}
