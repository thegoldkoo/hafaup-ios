#!/usr/bin/env python3
import glob
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import zipfile


WIDGET_NAME = "HafaUpWidget"
APP_NAME = "HafaUp"


def fail(message):
    print(f"[verify-live-activity-ipa] ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def run_plutil_json(path):
    try:
        output = subprocess.check_output(
            ["/usr/bin/plutil", "-convert", "json", "-o", "-", path],
            stderr=subprocess.STDOUT,
        )
        import json

        return json.loads(output.decode("utf-8"))
    except Exception as exc:
        fail(f"failed to read plist {path}: {exc}")


def read_plist(path):
    try:
        with open(path, "rb") as file:
            return plistlib.load(file)
    except Exception:
        return run_plutil_json(path)


def main():
    ipa = sys.argv[1] if len(sys.argv) > 1 else None
    if not ipa:
        matches = sorted(glob.glob("build/ios/ipa/*.ipa"))
        if not matches:
            fail("no IPA found under build/ios/ipa")
        ipa = matches[-1]

    if not os.path.exists(ipa):
        fail(f"IPA not found: {ipa}")

    with tempfile.TemporaryDirectory() as tmp:
        with zipfile.ZipFile(ipa) as archive:
            archive.extractall(tmp)

        app_dir = os.path.join(tmp, "Payload", f"{APP_NAME}.app")
        if not os.path.isdir(app_dir):
            payload_apps = glob.glob(os.path.join(tmp, "Payload", "*.app"))
            if not payload_apps:
                fail("Payload does not contain an .app")
            app_dir = payload_apps[0]

        app_plist_path = os.path.join(app_dir, "Info.plist")
        app_plist = read_plist(app_plist_path)
        if app_plist.get("NSSupportsLiveActivities") is not True:
            fail("main app Info.plist is missing NSSupportsLiveActivities=true")

        plug_ins_dir = os.path.join(app_dir, "PlugIns")
        if not os.path.isdir(plug_ins_dir):
            fail("main app has no PlugIns directory; widget extension is not embedded")

        appex_dir = os.path.join(plug_ins_dir, f"{WIDGET_NAME}.appex")
        if not os.path.isdir(appex_dir):
            found = [os.path.basename(path) for path in glob.glob(os.path.join(plug_ins_dir, "*.appex"))]
            fail(f"{WIDGET_NAME}.appex is not embedded. Found: {found}")

        widget_binary = os.path.join(appex_dir, WIDGET_NAME)
        if not os.path.exists(widget_binary):
            fail(f"widget executable missing: {widget_binary}")

        widget_plist_path = os.path.join(appex_dir, "Info.plist")
        widget_plist = read_plist(widget_plist_path)
        extension = widget_plist.get("NSExtension") or {}
        extension_point = extension.get("NSExtensionPointIdentifier")
        if extension_point != "com.apple.widgetkit-extension":
            fail(f"widget extension point is {extension_point!r}, expected com.apple.widgetkit-extension")
        if widget_plist.get("NSSupportsLiveActivities") is not True:
            fail("widget Info.plist is missing NSSupportsLiveActivities=true")

        strings_bin = shutil.which("strings")
        if strings_bin:
            try:
                strings_output = subprocess.check_output([strings_bin, widget_binary], stderr=subprocess.DEVNULL)
                strings_text = strings_output.decode("utf-8", errors="ignore")
                if "ShipmentLiveActivityWidget" not in strings_text and "ShipmentAttributes" not in strings_text:
                    print("[verify-live-activity-ipa] WARN: widget symbols are stripped or not visible to strings")
            except subprocess.CalledProcessError as exc:
                fail(f"strings failed for widget binary: {exc}")

        print(f"[verify-live-activity-ipa] OK: {ipa}")
        print(f"[verify-live-activity-ipa] embedded: Payload/{os.path.basename(app_dir)}/PlugIns/{WIDGET_NAME}.appex")
        print(f"[verify-live-activity-ipa] app version={app_plist.get('CFBundleShortVersionString')} build={app_plist.get('CFBundleVersion')}")
        print(f"[verify-live-activity-ipa] widget version={widget_plist.get('CFBundleShortVersionString')} build={widget_plist.get('CFBundleVersion')}")


if __name__ == "__main__":
    main()
