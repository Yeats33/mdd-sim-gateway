import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


class MacPcscBridgePackagingTests(unittest.TestCase):
    def test_vm_exposes_only_the_loopback_bridge_port(self):
        template = (ROOT / "native/mdd-hostd/templates/mdd-vm.yaml").read_text(
            encoding="utf-8"
        )
        self.assertIn("guestPort: 32512", template)
        self.assertIn("hostPort: 32512", template)
        bridge = template.split("guestPort: 32512", 1)[1]
        self.assertIn("hostIP: 127.0.0.1", bridge)

    def test_guest_uses_an_isolated_single_slot_vpcd_driver(self):
        installer = (ROOT / "install.sh").read_text(encoding="utf-8")
        self.assertIn("MACOS_PCSC_SLOT_COUNT=1", installer)
        self.assertIn('FRIENDLYNAME "Mac USB Smart Card Bridge"', installer)
        self.assertIn("libifdvpcd-macos.so", installer)

    def test_host_bridge_does_not_log_apdu_payloads(self):
        source = (ROOT / "native/mdd-hostd/src/pcsc_bridge.rs").read_text(
            encoding="utf-8"
        )
        self.assertIn(".transmit(&payload, &mut response)", source)
        self.assertNotIn("APDU -->", source)
        self.assertNotIn("hex::encode", source)


if __name__ == "__main__":
    unittest.main()
