#!/usr/bin/env python3
"""Verify an independent Simulator display, remote input, video and hotplug."""

import argparse
import platform
import plistlib
import subprocess
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("device", help="UDID of the dedicated iPhone or iPad Simulator")
parser.add_argument(
    "--output-path", type=Path, help="New directory for logs, screenshots and xcresult"
)
parser.add_argument(
    "--geometry",
    default="1920x1080",
    help="External framebuffer geometry supported by this runtime (legacy runtimes use 720x480).",
)
options = parser.parse_args()
output = (
    options.output_path or ROOT / ".build/external-display-tests" / str(uuid.uuid4())
).resolve()
output.mkdir(parents=True, exist_ok=False)
products = ROOT / ".build/mobile/Build/Products"


def run(*arguments, **kwargs):
    return subprocess.run(arguments, cwd=ROOT, check=True, **kwargs)


def screen(*arguments):
    run("xcrun", "simctl", "io", options.device, "screenConfig", "--display=external", *arguments)


def capture(name):
    for display in ("external", "internal"):
        run(
            "xcrun",
            "simctl",
            "io",
            options.device,
            "screenshot",
            "--display=" + display,
            str(output / (name + "-" + display + ".png")),
        )


run("python3", "scripts/create-xcode-project.py")
subprocess.run(
    ["xcrun", "simctl", "boot", options.device], cwd=ROOT, capture_output=True, check=False
)
run("xcrun", "simctl", "bootstatus", options.device, "-b")
screen("power", "off")
screen("geometry", options.geometry)
screen("power", "on")
with (output / "build.log").open("w") as log:
    run(
        "xcodebuild",
        "-project",
        "Plinth.xcodeproj",
        "-scheme",
        "PlinthMobile",
        "-destination",
        "platform=iOS Simulator,id=" + options.device,
        "-derivedDataPath",
        ".build/mobile",
        "build-for-testing",
        stdout=log,
        stderr=subprocess.STDOUT,
    )

sdk = run(
    "xcrun", "--sdk", "iphonesimulator", "--show-sdk-version", capture_output=True, text=True
).stdout.strip()
generated = products / (
    "PlinthMobile_iphonesimulator" + sdk + "-" + platform.machine() + ".xctestrun"
)
if not generated.exists():
    candidates = list(products.glob("PlinthMobile_iphonesimulator*.xctestrun"))
    if len(candidates) != 1:
        raise SystemExit("Expected exactly one generated mobile Simulator test configuration")
    generated = candidates[0]
configuration = plistlib.loads(generated.read_bytes())
configuration["KioskMobileUITests"]["EnvironmentVariables"]["PLINTH_EXTERNAL_HOTPLUG_TEST"] = "1"
owned_configuration = products / ("external-display-" + str(uuid.uuid4()) + ".xctestrun")
owned_configuration.write_bytes(plistlib.dumps(configuration))
test_log = output / "test.log"
print("EXTERNAL_TEST_OUTPUT=" + str(output), flush=True)
with test_log.open("w") as log:
    process = subprocess.Popen(
        [
            "xcodebuild",
            "-xctestrun",
            str(owned_configuration),
            "-destination",
            "platform=iOS Simulator,id=" + options.device,
            "-resultBundlePath",
            str(output / "tests.xcresult"),
            "-only-testing:KioskMobileUITests/MobileWorkflowUITests/testDisplayOnlyExternalOutputAndAdministratorRecovery",
            "-only-testing:KioskMobileUITests/MobileWorkflowUITests/testExternalTouchDragAndAudioActivation",
            "-only-testing:KioskMobileUITests/MobileWorkflowUITests/testExternalVideoDisconnectAndReconnect",
            "test-without-building",
        ],
        cwd=ROOT,
        stdout=log,
        stderr=subprocess.STDOUT,
    )
    print("EXTERNAL_TEST_PID=" + str(process.pid), flush=True)
    deadline = time.monotonic() + 240
    completed = set()
    phases = (
        ("EXTERNAL_SCROLL_VISIBLE", "scroll", None),
        ("EXTERNAL_VIDEO_DISCONNECT_READY", "playing", "off"),
        ("EXTERNAL_VIDEO_RECONNECT_READY", None, "on"),
        ("EXTERNAL_VIDEO_RESTARTED", "restarted", "off"),
    )
    try:
        while process.poll() is None:
            contents = test_log.read_text()
            for marker, screenshot, power in phases:
                if marker in contents and marker not in completed:
                    if screenshot:
                        capture(screenshot)
                    if power is not None:
                        screen("power", power)
                    completed.add(marker)
                    print(marker + "_CONTROL_COMPLETE", flush=True)
            if time.monotonic() >= deadline:
                raise TimeoutError("External display UI test exceeded its deadline")
            # Poll only to coordinate CLI actions; assertions wait for actual UI/DOM state.
            time.sleep(0.1)
        status = process.wait()
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    (output / "exit").write_text(str(status) + "\n")
    if status != 0 or len(completed) != len(phases):
        raise SystemExit("External display test failed; inspect " + str(test_log))
run(
    "xcrun",
    "xcresulttool",
    "export",
    "attachments",
    "--path",
    str(output / "tests.xcresult"),
    "--output-path",
    str(output / "attachments"),
)
print("EXTERNAL_TEST_PASSED=" + str(output), flush=True)
