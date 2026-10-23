"""Exercise the sender without collecting host data or contacting its endpoint."""

import configparser
import http.server
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = Path(os.environ.get("SENDER_SCRIPT_UNDER_TEST", ROOT / "agent_send_state.sh"))


class SenderTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="sender-test-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.bin = self.directory / "bin"
        self.bin.mkdir()
        self.received = []
        self.status = 200
        outer = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
                outer.received.append((self.headers.get("Content-Type"), body))
                self.send_response(outer.status)
                self.end_headers()
                self.wfile.write(b'{"fixture":true}')

            def log_message(self, *args):
                pass

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.stop_server)
        self.write_command("systemctl", """
import os, sys
if os.environ.get('SENDER_COLLECTOR_FAILURE') == '1':
    sys.exit(23)
print('fixture.service loaded active running fixture')
""")
        self.write_command("ps", """
import os
print('fixture-process ' + 'x' * int(os.environ.get('SENDER_FIXTURE_BYTES', '16')) + ' "quoted"')
""")
        self.write_command("curl", """
import os, subprocess, sys
from pathlib import Path
arguments = sys.argv[1:]
arguments[-1] = os.environ['SENDER_TEST_TARGET']
Path(os.environ['SENDER_CAPTURE']).write_text(str(sum(len(os.fsencode(a)) for a in arguments)))
payload = sys.stdin.buffer.read()
result = subprocess.run([os.environ['SENDER_REAL_CURL'], *arguments], input=payload,
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=40)
sys.stdout.buffer.write(result.stdout)
sys.stderr.buffer.write(result.stderr)
sys.exit(result.returncode)
""")
        self.environment = {
            **{
                key: value for key, value in os.environ.items()
                if key not in {"BASH_ENV", "ENV"} and not key.startswith("BASH_FUNC_")
            },
            "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
            "SENDER_TEST_TARGET": f"http://127.0.0.1:{self.server.server_port}/state",
            "SENDER_REAL_CURL": shutil.which("curl") or "",
            "SENDER_CAPTURE": str(self.directory / "curl-argv-bytes"),
            "SENDER_COLLECTOR_FAILURE": "0",
            "SENDER_FIXTURE_BYTES": "16",
            "NO_PROXY": "127.0.0.1,localhost",
            "no_proxy": "127.0.0.1,localhost",
        }
        self.assertTrue(self.environment["SENDER_REAL_CURL"], "curl is required")
        self.assertIsNotNone(shutil.which("jq"), "jq is required")

    def stop_server(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)

    def write_command(self, name, source):
        path = self.bin / name
        path.write_text(
            "#!" + sys.executable + "\nimport sys\n"
            "if sys.argv[1:] == ['--sender-fixture-check']:\n"
            f"    print({name!r})\n    sys.exit(0)\n" + source
        )
        path.chmod(0o755)
        # On noexec mounts Bash may search past an unusable PATH entry and
        # invoke the real collector. Probe absolute wrappers before the sender.
        try:
            probe = subprocess.run(
                [str(path), "--sender-fixture-check"], capture_output=True,
                text=True, timeout=5, check=False,
            )
        except OSError as error:
            self.fail(f"Cannot execute isolated {name} fixture: {error}")
        self.assertEqual(probe.returncode, 0, probe.stderr)
        self.assertEqual(probe.stdout.strip(), name)

    def run_sender(self):
        return subprocess.run(
            ["bash", str(SCRIPT)], env=self.environment,
            capture_output=True, text=True, timeout=45, check=False,
        )

    def test_large_payload_is_not_passed_as_a_command_argument(self):
        fixture_bytes = max(os.sysconf("SC_ARG_MAX") + 4096, 512 * 1024)
        self.environment["SENDER_FIXTURE_BYTES"] = str(fixture_bytes)
        result = self.run_sender()
        self.assertEqual(result.returncode, 0, result.stderr[:500])
        self.assertEqual(len(self.received), 1)
        content_type, body = self.received[0]
        self.assertEqual(content_type, "application/json")
        payload = json.loads(body)
        self.assertEqual(payload["services"], ["fixture.service"])
        self.assertEqual(len(payload["processes"]), 1)
        self.assertGreater(len(payload["processes"][0]), fixture_bytes)
        argv_bytes = int(Path(self.environment["SENDER_CAPTURE"]).read_text())
        self.assertLess(argv_bytes, 4096)

    def test_http_failure_is_a_failed_service_execution(self):
        self.status = 500
        result = self.run_sender()
        self.assertEqual(result.returncode, 22, result.stderr[:500])
        self.assertEqual(len(self.received), 1)

    def test_failed_collection_does_not_post_partial_state(self):
        self.environment["SENDER_COLLECTOR_FAILURE"] = "1"
        result = self.run_sender()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.received, [])
        self.assertFalse(Path(self.environment["SENDER_CAPTURE"]).exists())

    def test_unit_copies_have_the_same_semantics(self):
        primary = configparser.ConfigParser(interpolation=None)
        secondary = configparser.ConfigParser(interpolation=None)
        primary.read(ROOT / "agent_send_state.service")
        secondary.read(ROOT / "services/agent_send_state.service")
        self.assertEqual(primary.sections(), ["Unit", "Service", "Install"])
        self.assertEqual(
            {s: dict(primary[s]) for s in primary.sections()},
            {s: dict(secondary[s]) for s in secondary.sections()},
        )


if __name__ == "__main__":
    unittest.main()
