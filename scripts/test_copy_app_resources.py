"""Run the app resource copier against a package with app and test bundles."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "copy-app-resources.py"


class CopyAppResourcesTests(unittest.TestCase):
    def test_app_receives_all_dependency_bundles_and_no_test_bundle(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            products, resources = root / "products", root / "app-resources"
            products.mkdir()
            resources.mkdir()
            for name in ("Plinth_TextAssets", "Plinth_Images", "Plinth_KioskNativeTests"):
                (products / f"{name}.bundle").mkdir()
                (products / f"{name}.bundle" / "item").write_text(name)
            (resources / "Plinth_KioskNativeTests.bundle").mkdir()
            manifest = {
                "name": "Plinth",
                "targets": [
                    {"name": "Plinth", "dependencies": [{"byName": ["Feature", None]}]},
                    {
                        "name": "Feature",
                        "dependencies": [
                            {"byName": ["TextAssets", None]},
                            {"byName": ["Images", None]},
                        ],
                    },
                    {"name": "TextAssets", "resources": [{"path": "Text.xcstrings"}]},
                    {"name": "Images", "resources": [{"path": "Image.png"}]},
                    {"name": "KioskNativeTests", "resources": [{"path": "fixture.mp4"}]},
                ],
            }
            result = subprocess.run(
                [sys.executable, str(SCRIPT), str(products), str(resources)],
                input=json.dumps(manifest),
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(
                {path.name for path in resources.iterdir()},
                {"Plinth_TextAssets.bundle", "Plinth_Images.bundle"},
            )
            self.assertEqual(
                (resources / "Plinth_Images.bundle" / "item").read_text(), "Plinth_Images"
            )


if __name__ == "__main__":
    unittest.main()
