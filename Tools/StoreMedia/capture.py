#!/usr/bin/env python3
"""App Store capture (owner 2026-10-09): raw screenshots and clips for the
store screenshots and the preview video, from the iOS simulator.

    python3 Tools/StoreMedia/capture.py build            # Release simulator build
    python3 Tools/StoreMedia/capture.py menus  [iphone|ipad] [lang ...]
    python3 Tools/StoreMedia/capture.py stage  [iphone|ipad] <stage> <seconds> [difficulty]
    python3 Tools/StoreMedia/capture.py all

Output: .build/store/raw/<device>/... (gitignored). Every run is driven by
the app's capture switches: SPARKTREAD_AUTOSTART=<n> (play stage n),
SPARKTREAD_PILOT (the autopilot plays), SPARKTREAD_CUE_LOG (every sound
that starts is logged, because simulator recordings carry no audio),
SPARKTREAD_DIFFICULTY, SPARKTREAD_SCREEN=select. Progress is seeded so
every stage is open; Firebase never configures in the simulator.
"""
import json
import os
import shutil
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, ".build", "store", "raw")
DERIVED = os.path.join(ROOT, ".build", "DerivedData-store")
APP = os.path.join(DERIVED, "Build", "Products", "Release-iphonesimulator", "SparkTread.app")
BUNDLE = "io.icell.sparktread"
DEVICES = {"iphone": "iPhone 17 Pro Max", "ipad": "iPad Pro 13-inch (M5)"}
RUNTIME = "iOS-26-5"
LANGS = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "es"]
# One stage per theme, with the most to show: foliage and the fire weapon
# (2), water and amphibious flanks (4), ice and fast enemies (10), all five
# weapon families at once (12).
STAGES = [2, 4, 10, 12]
LOCALES = {"en": "en_US", "zh-Hans": "zh_CN", "zh-Hant": "zh_TW", "ja": "ja_JP", "ko": "ko_KR", "es": "es_ES"}


def run(*args, check=True, **kw):
    return subprocess.run(list(args), check=check, text=True, capture_output=True, **kw)


def udid(kind):
    devices = json.loads(run("xcrun", "simctl", "list", "devices", "available", "-j").stdout)["devices"]
    for runtime, entries in devices.items():
        if runtime.endswith(RUNTIME):
            for d in entries:
                if d["name"] == DEVICES[kind]:
                    return d["udid"]
    sys.exit(f"no {DEVICES[kind]} simulator on {RUNTIME}")


def build():
    subprocess.run(["xcodegen", "generate", "-q"], cwd=ROOT, check=True)
    subprocess.run(["xcodebuild", "build", "-project", "SparkTread.xcodeproj", "-scheme", "SparkTread",
                    "-configuration", "Release", "-sdk", "iphonesimulator",
                    "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", DERIVED,
                    "CODE_SIGNING_ALLOWED=NO", "-quiet"], cwd=ROOT, check=False)
    if not os.path.isdir(APP):
        sys.exit("simulator build failed")


def prepare(dev):
    run("xcrun", "simctl", "boot", dev, check=False)
    run("xcrun", "simctl", "bootstatus", dev, "-b")
    run("xcrun", "simctl", "install", dev, APP)
    run("xcrun", "simctl", "status_bar", dev, "override", "--time", "9:41", "--batteryState", "charged",
        "--batteryLevel", "100", "--wifiBars", "3", "--cellularBars", "4", check=False)
    seed_progress(dev)


def container(dev):
    return run("xcrun", "simctl", "get_app_container", dev, BUNDLE, "data").stdout.strip()


def seed_progress(dev):
    """Every stage open (eleven cleared), a best score, no run to continue."""
    campaign = json.load(open(os.path.join(ROOT, "Content", "campaigns", "campaign_v1.json")))
    folder = os.path.join(container(dev), "Library", "Application Support", "SparkTread")
    os.makedirs(folder, exist_ok=True)
    for name in ("suspended_session.json",):
        path = os.path.join(folder, name)
        if os.path.exists(path):
            os.remove(path)
    with open(os.path.join(folder, "campaign_progress.json"), "w") as f:
        json.dump({"schemaVersion": 1, "campaignID": campaign["id"],
                   "completedStageIDs": campaign["stageIDs"][:11], "bestScore": 48250}, f)


def launch(dev, lang, env):
    run("xcrun", "simctl", "terminate", dev, BUNDLE, check=False)
    full = dict(os.environ)
    for k, v in env.items():
        full["SIMCTL_CHILD_" + k] = v
    subprocess.run(["xcrun", "simctl", "launch", dev, BUNDLE, "-AppleLanguages", f"({lang})",
                    "-AppleLocale", LOCALES[lang]], env=full, check=True, capture_output=True)


def screenshot(dev, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    run("xcrun", "simctl", "io", dev, "screenshot", "--type=png", path)


class Recording:
    """simctl recordVideo in the background; `started` is the wall-clock
    time its first frame was taken (to within the polling step)."""

    def __init__(self, dev, path):
        self.log = path + ".log"
        self.proc = subprocess.Popen(["xcrun", "simctl", "io", dev, "recordVideo", "--codec=h264", "--force", path],
                                     stdout=open(self.log, "w"), stderr=subprocess.STDOUT)
        deadline = time.time() + 15
        while time.time() < deadline:
            if "Recording started" in open(self.log).read():
                break
            time.sleep(0.02)
        self.started = time.time()

    def stop(self):
        self.proc.send_signal(2)
        self.proc.wait(timeout=30)


def menus(kind, langs):
    dev = udid(kind)
    prepare(dev)
    for lang in langs:
        folder = os.path.join(OUT, kind, lang)
        os.makedirs(folder, exist_ok=True)
        # The title with its launch drive: recorded (the preview opens on
        # it) with the sounds logged, then the settled screen.
        rec = Recording(dev, os.path.join(folder, "title.mp4")) if kind == "iphone" else None
        launch(dev, lang, {"SPARKTREAD_CUE_LOG": "1"})
        time.sleep(9)
        screenshot(dev, os.path.join(folder, "title.png"))
        if rec:
            rec.stop()
            save_cues(dev, folder, "title", rec.started)
        launch(dev, lang, {"SPARKTREAD_SCREEN": "select"})
        time.sleep(3)
        screenshot(dev, os.path.join(folder, "select.png"))
        print(f"{kind} {lang}: title, select")


def save_cues(dev, folder, name, started):
    src = os.path.join(container(dev), "tmp", "cue_log.txt")
    if os.path.exists(src):
        shutil.copy(src, os.path.join(folder, name + "_cues.txt"))
    with open(os.path.join(folder, name + "_start.txt"), "w") as f:
        f.write(f"{started:.4f}\n")


def stage(kind, number, seconds, difficulty="standard", every=2.0):
    dev = udid(kind)
    prepare(dev)
    folder = os.path.join(OUT, kind, f"stage{number:02d}")
    shutil.rmtree(folder, ignore_errors=True)
    os.makedirs(folder)
    rec = Recording(dev, os.path.join(folder, "play.mp4")) if kind == "iphone" else None
    launch(dev, "en", {"SPARKTREAD_AUTOSTART": str(number), "SPARKTREAD_PILOT": "1",
                       "SPARKTREAD_CUE_LOG": "1", "SPARKTREAD_DIFFICULTY": difficulty})
    t0 = time.time()
    i = 0
    while time.time() - t0 < seconds:
        time.sleep(every)
        i += 1
        screenshot(dev, os.path.join(folder, f"shot_{i:03d}_{time.time() - t0:05.1f}.png"))
    if rec:
        rec.stop()
        save_cues(dev, folder, "play", rec.started)
    print(f"{kind} stage {number}: {i} screenshots" + (", video" if rec else ""))


if __name__ == "__main__":
    args = sys.argv[1:] or ["all"]
    cmd = args[0]
    if cmd == "build":
        build()
    elif cmd == "menus":
        menus(args[1] if len(args) > 1 else "iphone", args[2:] or LANGS)
    elif cmd == "stage":
        stage(args[1], int(args[2]), float(args[3]), args[4] if len(args) > 4 else "standard")
    elif cmd == "all":
        build()
        for n in STAGES:
            stage("iphone", n, 150, every=1.0)
        menus("iphone", LANGS)  # V1 is iPhone only (ADR-0028); "ipad" still works on request
    else:
        sys.exit(__doc__)
