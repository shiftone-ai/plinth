import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("check-public-content.py")


class PublicContentCheckTests(unittest.TestCase):
    def test_staged_content_is_checked_even_if_worktree_was_cleaned(self):
        with tempfile.TemporaryDirectory() as directory:
            env = os.environ.copy()
            names = subprocess.check_output(["git", "rev-parse", "--local-env-vars"])
            for name in names.decode().splitlines():
                env.pop(name, None)
            subprocess.run(["git", "init", "-q"], cwd=directory, env=env, check=True)
            path = Path(directory) / "draft.md"
            address = "person" + "@" + "private.invalid"
            path.write_text(f"Contact {address}.\n")
            subprocess.run(["git", "add", "draft.md"], cwd=directory, env=env, check=True)
            path.write_text("Public text only.\n")

            result = subprocess.run(
                ["python3", str(SCRIPT), "--staged"],
                cwd=directory,
                env=env,
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 1)
            self.assertIn("draft.md:1", result.stdout)
            self.assertNotIn(address, result.stdout)

    def test_reports_private_contact_without_echoing_it(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "draft.md"
            address = "person" + "@" + "private.invalid"
            path.write_text(f"Contact {address} for the internal service.\n")
            result = subprocess.run(
                ["python3", str(SCRIPT), str(path)],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 1)
            self.assertIn("review public content", result.stdout)
            self.assertNotIn(address, result.stdout)

    def test_accepts_documentation_example_address(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "example.md"
            path.write_text("Use reader@example.com in the fixture.\n")
            result = subprocess.run(
                ["python3", str(SCRIPT), str(path)],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0)

    def test_reports_internal_service_note(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "note.md"
            service = "Google " + "Workspace"
            path.write_text(f"Checked {service} settings.\n")
            result = subprocess.run(
                ["python3", str(SCRIPT), str(path)],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 1)
            self.assertNotIn(service, result.stdout)
