#!/usr/bin/env python3
"""Frame Studio dev server. Serves the visual editor plus a tiny API over the
screenshot pipeline files. Start via bin/frame-studio.sh (it compiles the
compositor first); runs from the repo root.

GET  /fastlane/...                     static files (no-cache)
GET  /api/state                        locales, scenes, layout, fonts, frames, images
GET  /api/titles/<locale>              title.strings as JSON
GET  /api/font?path=<path>             font bytes (repo fonts dir or system fonts only)
PUT  /api/layout                       write layout.json
PUT  /api/titles/<locale>              write title.strings from JSON
POST /api/compose {scene?, locale?}    run the compositor, in place
POST /api/upload {name, data}          save a base64 image into frame-studio/images
"""

import base64
import json
import re
import subprocess
import sys
import webbrowser
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
STUDIO = ROOT / "fastlane" / "frame-studio"
SCREENSHOTS = ROOT / "fastlane" / "screenshots"
COMPOSE = STUDIO / ".build" / "compose"
PORT = 8765

LOCALE_RE = re.compile(r"^[A-Za-z]{2}(-[A-Za-z]{2})?$")


def locales():
    # Only locales that actually have captures — parked ones (e.g. tr) keep
    # their title.strings but should not appear in the editor.
    return sorted(
        d.name for d in SCREENSHOTS.iterdir()
        if d.is_dir() and d.name != "fonts" and LOCALE_RE.match(d.name)
        and any(True for _ in d.glob("*-*.png"))
    )


def read_strings(path: Path) -> dict:
    """Parse a .strings file (UTF-8 or UTF-16, either byte order)."""
    raw = path.read_bytes()
    if raw.startswith(b"\xff\xfe") or raw.startswith(b"\xfe\xff"):
        text = raw.decode("utf-16")
    else:
        text = raw.decode("utf-8")
    result = {}
    for m in re.finditer(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', text):
        key, value = (
            s.replace(r"\n", "\n").replace(r"\"", '"').replace("\\\\", "\\")
            for s in (m.group(1), m.group(2))
        )
        result[key] = value
    return result


def write_strings(path: Path, entries: dict):
    def esc(s):
        return s.replace("\\", "\\\\").replace('"', r"\"").replace("\n", r"\n")

    body = "\n".join(f'"{esc(k)}" = "{esc(v)}";' for k, v in sorted(entries.items()))
    path.write_text(body + "\n", encoding="utf-8")


class Handler(SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):  # quieter console
        pass

    def send_json(self, obj, status=200):
        data = json.dumps(obj).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def body_json(self):
        length = int(self.headers.get("Content-Length", 0))
        return json.loads(self.rfile.read(length) or b"{}")

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    # -- GET ------------------------------------------------------------

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/":
            self.send_response(302)
            self.send_header("Location", "/fastlane/frame-studio/editor.html")
            self.end_headers()
            return
        if path == "/api/state":
            layout = json.loads((STUDIO / "layout.json").read_text())
            first = SCREENSHOTS / locales()[0]
            scenes = sorted(
                p.name[: -len(".png")].split("-", 1)
                for p in first.glob("*.png")
                if "-" in p.name and "_framed" not in p.name
                and "watch" not in p.name.lower()
            )
            self.send_json({
                "locales": locales(),
                "device": scenes[0][0] if scenes else "",
                "scenes": [s[1] for s in scenes],
                "layout": layout,
                "fonts": sorted(p.name for p in (SCREENSHOTS / "fonts").glob("*.[ot]tf")),
                # The system families SwiftUI offers (SF Pro = .default,
                # .rounded, .compact on watchOS, .monospaced, .serif). All are
                # variable fonts — the editor's Weight control picks the style.
                "systemFonts": [
                    {"name": name, "path": path}
                    for name, path in [
                        ("SF Pro", "/System/Library/Fonts/SFNS.ttf"),
                        ("SF Pro Rounded", "/System/Library/Fonts/SFNSRounded.ttf"),
                        ("SF Compact", "/System/Library/Fonts/SFCompact.ttf"),
                        ("SF Mono", "/System/Library/Fonts/SFNSMono.ttf"),
                        ("New York", "/System/Library/Fonts/NewYork.ttf"),
                    ]
                    if Path(path).exists()
                ],
                "frames": sorted(p.stem for p in (STUDIO / "frames").glob("*.png")),
                "images": sorted(
                    p.name for p in (STUDIO / "images").glob("*.*")
                    if p.suffix.lower() in (".png", ".jpg", ".jpeg", ".webp")
                ) if (STUDIO / "images").is_dir() else [],
                "watchShots": {
                    loc: sorted(
                        p.name for p in (SCREENSHOTS / loc).glob("*.png")
                        if "watch" in p.name.lower() and "_framed" not in p.name
                    )
                    for loc in locales()
                },
            })
            return
        if path.startswith("/api/titles/"):
            locale = path.rsplit("/", 1)[1]
            file = SCREENSHOTS / locale / "title.strings"
            if not LOCALE_RE.match(locale) or not file.exists():
                self.send_json({"error": "unknown locale"}, 404)
                return
            self.send_json(read_strings(file))
            return
        if path == "/api/font":
            query = self.path.split("?", 1)[1] if "?" in self.path else ""
            font_path = ""
            for part in query.split("&"):
                if part.startswith("path="):
                    from urllib.parse import unquote
                    font_path = unquote(part[len("path="):])
            resolved = (
                Path(font_path) if font_path.startswith("/")
                else SCREENSHOTS / font_path
            ).resolve()
            allowed = (
                str(resolved).startswith(str((SCREENSHOTS / "fonts").resolve()))
                or str(resolved).startswith("/System/Library/Fonts/")
                or str(resolved).startswith(str(Path.home() / "Library/Fonts"))
            )
            if not allowed or resolved.suffix.lower() not in (".otf", ".ttf") or not resolved.exists():
                self.send_json({"error": "font not allowed"}, 404)
                return
            data = resolved.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "font/otf")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        super().do_GET()

    # -- PUT ------------------------------------------------------------

    def do_PUT(self):
        if self.path == "/api/layout":
            layout = self.body_json()
            (STUDIO / "layout.json").write_text(
                json.dumps(layout, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
            )
            self.send_json({"ok": True})
            return
        if self.path.startswith("/api/titles/"):
            locale = self.path.rsplit("/", 1)[1]
            if not LOCALE_RE.match(locale) or not (SCREENSHOTS / locale).is_dir():
                self.send_json({"error": "unknown locale"}, 404)
                return
            write_strings(SCREENSHOTS / locale / "title.strings", self.body_json())
            self.send_json({"ok": True})
            return
        self.send_json({"error": "not found"}, 404)

    # -- POST -----------------------------------------------------------

    def do_POST(self):
        if self.path == "/api/upload":
            body = self.body_json()
            name = re.sub(r"[^A-Za-z0-9._-]", "_", Path(body.get("name", "image.png")).name)
            if Path(name).suffix.lower() not in (".png", ".jpg", ".jpeg", ".webp"):
                self.send_json({"error": "only png/jpg/webp"}, 400)
                return
            data = body.get("data", "")
            if data.startswith("data:"):
                data = data.split(",", 1)[1]
            images_dir = STUDIO / "images"
            images_dir.mkdir(exist_ok=True)
            dest = images_dir / name
            counter = 2
            while dest.exists():
                dest = images_dir / f"{Path(name).stem}-{counter}{Path(name).suffix}"
                counter += 1
            dest.write_bytes(base64.b64decode(data))
            self.send_json({"ok": True, "src": f"images/{dest.name}"})
            return
        if self.path == "/api/compose":
            body = self.body_json()
            cmd = [str(COMPOSE)]
            if body.get("scene"):
                cmd += ["--scene", body["scene"]]
            if body.get("locale"):
                cmd += ["--locale", body["locale"]]
            run = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=300)
            self.send_json({
                "ok": run.returncode == 0,
                "stdout": run.stdout,
                "stderr": run.stderr,
            })
            return
        self.send_json({"error": "not found"}, 404)


if __name__ == "__main__":
    import os

    os.chdir(ROOT)
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    url = f"http://127.0.0.1:{PORT}/"
    print(f"Frame Studio: {url}  (Ctrl-C to stop)")
    if "--no-browser" not in sys.argv:
        webbrowser.open(url)
    server.serve_forever()
