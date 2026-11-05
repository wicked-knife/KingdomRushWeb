"""Isolated native-window acceptance using the actual split Web PCKs and HTTP."""
import functools
import http.server
from pathlib import Path
import shutil
import subprocess
import threading

from web_bootstrap import ROOT, Handler, godot_path


class QuietHandler(Handler):
    def log_message(self, *_args): pass

    def copyfile(self, source, outputfile):
        try:
            super().copyfile(source, outputfile)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass  # Expected when foreground loading cancels a prefetch.


def main():
    directory = ROOT / "build/pack-native-check"
    directory.mkdir(parents=True, exist_ok=True)
    captures = ROOT / "output/web_packs_native"
    captures.mkdir(parents=True, exist_ok=True)
    (captures / "report.json").unlink(missing_ok=True)
    (directory / "project.godot").write_text('''config_version=5
[application]
config/name="Kingdom Rush Pack Acceptance"
[display]
window/size/viewport_width=1920
window/size/viewport_height=1080
window/size/window_width_override=1280
window/size/window_height_override=720
window/stretch/mode="canvas_items"
[rendering]
renderer/rendering_method="gl_compatibility"
''')
    shutil.copy2(ROOT / "tests/web_packs_native.gd", directory / "native.gd")
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(QuietHandler, directory=str(ROOT / "build/web")))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    url = f"http://127.0.0.1:{server.server_port}/"
    cache = directory / ("cache-" + str(__import__("time").time_ns()))
    try:
        result = subprocess.run([godot_path(), "--path", str(directory), "--position", "80,80", "--resolution", "1280x720", "--max-fps", "60", "--script", str(directory / "native.gd"), "--", str(ROOT / "build/web/index.pck"), url, str(captures), "--content-base-url=" + url, "--content-cache-root=" + str(cache)], timeout=180)
        if result.returncode: raise SystemExit(result.returncode)
    finally:
        server.shutdown()
        server.server_close()


if __name__ == "__main__": main()
