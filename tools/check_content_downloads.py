"""Run Godot's real HTTP downloader against deterministic local failure cases."""
import functools
import hashlib
import http.server
import json
from pathlib import Path
import subprocess
import tempfile
import threading
import time

from web_packs import Entry, write_pack, digest_file
from web_bootstrap import godot_path

ROOT = Path(__file__).resolve().parents[1]


class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_args): pass

    def do_GET(self):
        pieces = self.path.split("/", 2)
        mode = pieces[1]
        relative = pieces[2] if len(pieces) > 2 else ""
        if mode == "missing":
            self.send_error(404)
            return
        source = Path(self.directory) / relative
        if not source.is_file():
            self.send_error(404)
            return
        data = source.read_bytes()
        if mode == "corrupt": data = data[:-1] + bytes([data[-1] ^ 1])
        self.send_response(200)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if mode == "truncated": data = data[:len(data) // 2]
        try:
            for offset in range(0, len(data), 8192):
                self.wfile.write(data[offset:offset + 8192])
                self.wfile.flush()
                if mode == "slow": time.sleep(0.006)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError): pass
        self.close_connection = True


def main():
    (ROOT / "build").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="download-check-", dir=ROOT / "build") as temporary:
        directory = Path(temporary)
        (directory / "packs").mkdir()
        raw = directory / "empty"
        raw.touch()
        index = {"schema_version": 1, "engine_version": "4.7.2", "packs": {}, "bundles": {}}
        for letter in "abcdefg":
            data = (letter.encode() * (1024 * 1024))
            name = "pack_probe/" + letter + ".txt"
            entry = Entry(name, 0, len(data), hashlib.md5(data).digest(), hashlib.sha256(data).hexdigest(), data)
            target = directory / "temporary.pck"
            write_pack(raw, target, [{"entries": [entry]}])
            digest = digest_file(target)
            target.rename(directory / "packs" / (digest + ".pck"))
            index["packs"][digest] = {"url": "packs/" + digest + ".pck", "size": (directory / "packs" / (digest + ".pck")).stat().st_size, "sha256": digest}
            index["bundles"][letter] = [digest]
        fixture = directory / "fixture.json"
        fixture.write_text(json.dumps(index))
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Handler, directory=str(directory)))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            result = subprocess.run([godot_path(), "--headless", "--path", str(ROOT), "--max-fps", "120", "--script", "res://tests/verify_content_downloads.gd", "--", f"http://127.0.0.1:{server.server_port}/", str(fixture), str(directory / "cache")], timeout=90)
            if result.returncode: raise SystemExit(result.returncode)
        finally:
            server.shutdown()
            server.server_close()


if __name__ == "__main__": main()
