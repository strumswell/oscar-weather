#!/usr/bin/env python3
"""Social Studio: stage, capture and compose social-media shots of Oscar°.
Stdlib only. Start via bin/social-studio.sh; the GUI is index.html next to
this file (it also opens straight from disk as a plain editor, minus the
simulator panel).

GET  /                      the GUI
GET  /out|compositions|frames|shots|fonts/<file>   captures, saved compositions, device frames, …
GET  /api/state             devices, scenes, captures, frame geometry, ffmpeg
POST /api/<action>          see ACTIONS at the bottom
PUT  /api/upload?name=      raw file body: imports an image or video into out/
"""

import base64
import json
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import webbrowser
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote

STUDIO = Path(__file__).resolve().parent
ROOT = STUDIO.parent.parent
OUT = STUDIO / "out"
COMPOSITIONS = STUDIO / "compositions"
FRAME_STUDIO = ROOT / "fastlane" / "frame-studio"
STATIC = {
    "out": OUT,
    "compositions": COMPOSITIONS,
    "frames": FRAME_STUDIO / "frames",
    "shots": ROOT / "fastlane" / "screenshots",
    "fonts": ROOT / "fastlane" / "screenshots" / "fonts",
}
BUNDLE_ID = "cloud.bolte.Oscar"
PORT = 8766
UDID_RE = re.compile(r"^[0-9A-F-]{36}$")
MEDIA = (".png", ".jpg", ".jpeg", ".webp", ".gif", ".mov", ".mp4", ".m4v")
FFMPEG = shutil.which("ffmpeg")

recording = None  # (Popen, Path)


class Fail(Exception):
    pass


def run(*cmd, timeout=120):
    done = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if done.returncode != 0:
        raise Fail((done.stderr or done.stdout).strip() or f"{cmd[0]} failed")
    return done.stdout


def simctl(*args, **kw):
    return run("xcrun", "simctl", *args, **kw)


def udid(body):
    value = body.get("udid", "")
    if not UDID_RE.match(value):
        raise Fail("pick a simulator first")
    return value


def out_file(name):
    path = OUT / Path(name).name
    if not path.is_file():
        raise Fail(f"no such capture: {name}")
    return path


def stamp(suffix):
    OUT.mkdir(exist_ok=True)
    return OUT / f"{time.strftime('%Y%m%d-%H%M%S')}{suffix}"


def scenes():
    # Parsed from the enum so the list never drifts from the app.
    source = (ROOT / "Oscar°/Debug/Screenshots/ScreenshotMode.swift").read_text(encoding="utf-8")
    enum = source.split("enum ScreenshotScene", 1)[1].split("}", 1)[0]
    return re.findall(r"case (\w+)", enum)


def state(_):
    devices = []
    for runtime, entries in json.loads(simctl("list", "devices", "available", "-j"))["devices"].items():
        if "iOS" not in runtime:
            continue
        version = runtime.rsplit("iOS-", 1)[-1].replace("-", ".")
        devices += [
            {"udid": d["udid"], "name": f"{d['name']} · iOS {version}", "booted": d["state"] == "Booted"}
            for d in entries
        ]
    devices.sort(key=lambda d: (not d["booted"], d["name"]))
    OUT.mkdir(exist_ok=True)
    shots = STATIC["shots"]
    return {
        "devices": devices,
        "scenes": scenes(),
        "captures": sorted((p.name for p in OUT.iterdir() if p.suffix.lower() in MEDIA), reverse=True),
        "appStore": sorted(
            f"{p.parent.name}/{p.name}" for p in shots.glob("*/*.png") if "_framed" not in p.name
        ) if shots.is_dir() else [],
        "compositions": sorted(p.stem for p in COMPOSITIONS.glob("*.json")),
        "frames": sorted(p.name for p in STATIC["frames"].glob("*.png")),
        "frameGeometry": json.loads((FRAME_STUDIO / "layout.json").read_text())["device"],
        "fonts": sorted(p.name for p in STATIC["fonts"].glob("*.[ot]tf")) if STATIC["fonts"].is_dir() else [],
        "ffmpeg": bool(FFMPEG),
        "recording": recording is not None,
    }


def simulator_app():
    # Xcode 27 replaced Simulator.app with DeviceHub.app.
    xcode = Path(run("xcode-select", "-p").strip()).parent
    for app in (xcode / "Applications/DeviceHub.app", xcode / "Developer/Applications/Simulator.app"):
        if app.is_dir():
            return app
    raise Fail("no Simulator or DeviceHub app in the selected Xcode")


def boot(body):
    try:
        simctl("boot", udid(body))
    except Fail as error:
        if "current state: Booted" not in str(error):
            raise
    run("open", str(simulator_app()))


def launch(body):
    args = ["-hasCompletedOnboarding", "NO" if body.get("scene") == "onboarding" else "YES"]
    if body.get("scene"):
        if body["scene"] not in scenes():
            raise Fail("unknown scene")
        args += ["-screenshotScene", body["scene"]]
    for key in ("screenshotStory", "screenshotHour", "screenshotTemperature", "screenshotWeathercode",
                "screenshotPlace", "screenshotLiveActivityPhase", "onboardingStep"):
        value = str(body.get(key, "")).strip()
        if value:
            args += [f"-{key}", value]
    if body.get("language"):
        args += ["-AppleLanguages", f"({body['language']})", "-AppleLocale", body["language"].replace("-", "_")]
    args += shlex.split(body.get("extra", ""))
    simctl("launch", "--terminate-running-process", udid(body), BUNDLE_ID, *args)
    return {"args": args, "stale": build_is_stale(udid(body))}


def build_is_stale(device):
    """Fixtures and their overrides are compiled in: an installed build older
    than the fixture sources silently ignores whatever they added since."""
    app = Path(simctl("get_app_container", device, BUNDLE_ID).strip())
    built = max(p.stat().st_mtime for p in app.iterdir() if p.is_file())
    sources = (ROOT / "Oscar°/Debug/Screenshots").glob("*.swift")
    return built < max(p.stat().st_mtime for p in sources)


def terminate(body):
    simctl("terminate", udid(body), BUNDLE_ID)


def statusbar(body):
    device = udid(body)
    if body.get("clear"):
        simctl("status_bar", device, "clear")
        return
    network = body.get("network", "wifi")
    args = [
        "--time", body.get("time") or "9:41",
        "--dataNetwork", network,
        "--wifiMode", "active" if network == "wifi" else "failed",
        "--wifiBars", str(int(body.get("wifiBars", 3))),
        "--cellularMode", "active",
        "--cellularBars", str(int(body.get("cellularBars", 4))),
        "--operatorName", body.get("operator", ""),
        "--batteryState", body.get("batteryState", "discharging"),
        "--batteryLevel", str(int(body.get("batteryLevel", 100))),
    ]
    simctl("status_bar", device, "override", *args)


def appearance(body):
    simctl("ui", udid(body), "appearance", "light" if body.get("mode") == "light" else "dark")


def push(body):
    alert = {k: body[k] for k in ("title", "subtitle", "body") if body.get(k)}
    if not alert:
        raise Fail("give the notification a title or body")
    with tempfile.NamedTemporaryFile("w", suffix=".apns", delete=False) as payload:
        json.dump({"aps": {"alert": alert, "sound": "default"}}, payload)
    try:
        simctl("push", udid(body), BUNDLE_ID, payload.name)
    finally:
        Path(payload.name).unlink()


def menu(body):
    # simctl has no lock/home button; the simulator window's shortcuts do
    # (⌘L, ⇧⌘H). Shortcuts rather than menu items: menu titles are localized
    # and moved with Xcode 27's DeviceHub. Needs the Accessibility permission
    # for whatever runs this server.
    keys = {"lock": '"l" using command down', "home": '"h" using {command down, shift down}'}.get(body.get("item"))
    if not keys:
        raise Fail("unknown menu item")
    try:
        run("open", str(simulator_app()))
        time.sleep(0.4)
        run("osascript", "-e", f'tell application "System Events" to keystroke {keys}')
    except Fail as error:
        shortcut = "⌘L" if body["item"] == "lock" else "⇧⌘H"
        raise Fail(f"{error}\nGrant Accessibility to your terminal, or press {shortcut} in the simulator window.")


def shot(body):
    mask = body.get("mask", "alpha")
    if mask not in ("alpha", "black", "ignored"):
        raise Fail("unknown mask")
    path = stamp(".png")
    simctl("io", udid(body), "screenshot", "--type=png", f"--mask={mask}", str(path))
    return {"name": path.name}


def record_start(body):
    global recording
    if recording:
        raise Fail("already recording")
    codec = "hevc" if body.get("codec") == "hevc" else "h264"
    path = stamp(".mov")
    process = subprocess.Popen(
        ["xcrun", "simctl", "io", udid(body), "recordVideo", f"--codec={codec}", "--mask=black", "--force", str(path)],
        stderr=subprocess.PIPE, text=True,
    )
    # simctl announces the first processed frame on stderr.
    for line in process.stderr:
        if "Recording started" in line:
            break
    if process.poll() is not None:
        raise Fail("recordVideo exited right away")
    recording = (process, path)


def record_stop(_):
    global recording
    if not recording:
        raise Fail("not recording")
    process, path = recording
    recording = None
    process.send_signal(signal.SIGINT)
    process.wait(timeout=60)
    return {"name": path.name}


def duration(path):
    return float(run("ffprobe", "-v", "error", "-show_entries", "format=duration",
                     "-of", "csv=p=0", str(path)).strip())


def data_url_file(data, directory, name):
    path = Path(directory) / name
    path.write_bytes(base64.b64decode(data.split(",", 1)[1]))
    return path


def encode(body):
    """Composites under.png + the scaled recording + over.png (both rendered by
    the editor) into an H.264 mp4. `crf` for constant quality, `targetMB` for a
    two-pass fit to a size budget."""
    if not FFMPEG:
        raise Fail("ffmpeg not found (brew install ffmpeg)")
    source = out_file(body["name"])
    even = lambda v: max(2, int(round(float(v) / 2)) * 2)
    width, height = even(body["width"]), even(body["height"])
    x, y, w, h = (int(round(float(body[k]))) for k in ("x", "y", "w", "h"))
    fps = min(60, max(5, int(body.get("fps", 30))))
    start, end = float(body.get("start") or 0), float(body.get("end") or 0)
    trim = ["-ss", str(start)] + (["-to", str(end)] if end > start else [])
    length = (end if end > start else duration(source)) - start
    target = out_file(body["name"]).with_name(f"{source.stem}-{time.strftime('%H%M%S')}.mp4")

    with tempfile.TemporaryDirectory() as tmp:
        under = data_url_file(body["under"], tmp, "under.png")
        over = data_url_file(body["over"], tmp, "over.png")
        graph = (
            f"[1:v]scale={width}:{height}[u];[0:v]fps={fps},scale={even(w)}:{even(h)}[v];"
            f"[u][v]overlay={x}:{y}:shortest=1[a];[2:v]scale={width}:{height}[o];"
            "[a][o]overlay=0:0:shortest=1,format=yuv420p[out]"
        )
        base = [FFMPEG, "-y", "-v", "error", *trim, "-i", str(source),
                "-loop", "1", "-framerate", str(fps), "-i", str(under),
                "-loop", "1", "-framerate", str(fps), "-i", str(over),
                "-filter_complex", graph, "-map", "[out]", "-c:v", "libx264",
                "-preset", "slow", "-movflags", "+faststart", "-an"]
        if body.get("targetMB"):
            # 3 % headroom for the container.
            kbps = max(80, int(float(body["targetMB"]) * 8192 * 0.97 / max(length, 0.1)))
            rate = ["-b:v", f"{kbps}k", "-passlogfile", str(Path(tmp) / "pass")]
            run(*base, *rate, "-pass", "1", "-f", "null", "/dev/null", timeout=900)
            run(*base, *rate, "-pass", "2", str(target), timeout=900)
        else:
            run(*base, "-crf", str(int(body.get("crf", 23))), str(target), timeout=900)
    return {"name": target.name, "bytes": target.stat().st_size}


def composition_file(body):
    name = re.sub(r"[^\w .()-]", "_", str(body.get("name", ""))).strip(" .")
    if not name:
        raise Fail("give the composition a name")
    return COMPOSITIONS / f"{name}.json"


def comp_save(body):
    COMPOSITIONS.mkdir(exist_ok=True)
    path = composition_file(body)
    path.write_text(json.dumps(body["doc"], indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return {"name": path.stem}


def comp_delete(body):
    composition_file(body).unlink(missing_ok=True)


def delete(body):
    out_file(body["name"]).unlink()


def reveal(body):
    run("open", "-R", str(out_file(body["name"])) if body.get("name") else str(OUT))


ACTIONS = {f.__name__: f for f in (
    boot, launch, terminate, statusbar, appearance, push, menu, shot,
    record_start, record_stop, encode, delete, reveal, comp_save, comp_delete,
)}


class Handler(SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def send_json(self, obj, status=200):
        data = json.dumps(obj).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def translate_path(self, path):
        parts = unquote(path.split("?")[0]).strip("/").split("/")
        if parts == [""]:
            return str(STUDIO / "index.html")
        base = STATIC.get(parts[0])
        resolved = (base / "/".join(parts[1:])).resolve() if base else None
        if not resolved or not str(resolved).startswith(str(base.resolve()) + "/"):
            return str(STUDIO / "404")
        return str(resolved)

    def do_GET(self):
        if self.path == "/api/state":
            return self.respond(state, {})
        ranged = re.match(r"bytes=(\d+)-(\d*)$", self.headers.get("Range", ""))
        path = Path(self.translate_path(self.path))
        if not ranged or not path.is_file():
            return super().do_GET()
        # Safari refuses to play video from a server without byte ranges.
        size = path.stat().st_size
        first = int(ranged.group(1))
        last = min(int(ranged.group(2) or size - 1), size - 1)
        self.send_response(206)
        self.send_header("Content-Type", self.guess_type(str(path)))
        self.send_header("Content-Range", f"bytes {first}-{last}/{size}")
        self.send_header("Content-Length", str(last - first + 1))
        self.end_headers()
        with path.open("rb") as file:
            file.seek(first)
            self.wfile.write(file.read(last - first + 1))

    def foreign(self):
        # Only this page may drive the simulator, not any site open in the browser.
        origin = self.headers.get("Origin")
        if origin and origin != f"http://{self.headers.get('Host')}":
            self.send_json({"error": "foreign origin"}, 403)
            return True

    def do_PUT(self):
        if self.foreign():
            return
        if not self.path.startswith("/api/upload?name="):
            return self.send_json({"error": "not found"}, 404)
        name = re.sub(r"[^\w.() -]", "_", Path(unquote(self.path.split("=", 1)[1])).name)
        if Path(name).suffix.lower() not in MEDIA:
            return self.send_json({"error": "images and videos only"}, 400)
        OUT.mkdir(exist_ok=True)
        target, counter = OUT / name, 2
        while target.exists():
            target = OUT / f"{Path(name).stem}-{counter}{Path(name).suffix}"
            counter += 1
        with target.open("wb") as file:
            remaining = int(self.headers.get("Content-Length", 0))
            while remaining > 0:
                chunk = self.rfile.read(min(remaining, 1 << 20))
                if not chunk:
                    break
                file.write(chunk)
                remaining -= len(chunk)
        self.send_json({"name": target.name})

    def do_POST(self):
        if self.foreign():
            return
        action = ACTIONS.get(self.path.removeprefix("/api/"))
        if not action:
            return self.send_json({"error": "not found"}, 404)
        length = int(self.headers.get("Content-Length", 0))
        self.respond(action, json.loads(self.rfile.read(length) or b"{}"))

    def respond(self, action, body):
        try:
            self.send_json(action(body) or {"ok": True})
        except (Fail, KeyError, ValueError, subprocess.TimeoutExpired) as error:
            self.send_json({"error": str(error)}, 400)


if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    url = f"http://127.0.0.1:{PORT}/"
    print(f"Social Studio: {url}  (Ctrl-C to stop)")
    if "--no-browser" not in sys.argv:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        if recording:
            recording[0].send_signal(signal.SIGINT)
            recording[0].wait(timeout=60)
