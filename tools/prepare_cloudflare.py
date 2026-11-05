"""Stage an existing Godot Web export for Cloudflare Pages (25 MiB per asset)."""
import json
from pathlib import Path
import shutil
import tempfile
from web_packs import digest_file, LIMIT

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "build/web"
TARGET = ROOT / "build/cloudflare"
CHUNK = 24 * 1024 * 1024


def main():
    receipt = json.loads((SOURCE / "export_receipt.json").read_text())
    assert receipt["pck_isolated_check"], "Run export --check-pack first"
    assert digest_file(SOURCE / "index.pck") == receipt["pck_sha256"]
    assert digest_file(SOURCE / "web_packs.json") == receipt["packs_manifest_sha256"]
    index = json.loads((SOURCE / "web_packs.json").read_text())
    for row in index["packs"].values():
        source = SOURCE / row["url"]
        assert source.resolve().is_relative_to((SOURCE / "packs").resolve())
        assert source.stat().st_size == row["size"] <= LIMIT
        assert digest_file(source) == row["sha256"]
    staging = Path(tempfile.mkdtemp(prefix="cloudflare-stage-", dir=ROOT / "build"))
    target = staging
    manifest = {}
    for source in SOURCE.iterdir():
        if source.suffix not in {".html", ".js", ".png", ".pck", ".wasm"}:
            continue
        if source.stat().st_size <= CHUNK:
            shutil.copy2(source, target / source.name)
            continue
        digest = digest_file(source)
        parts = []
        with source.open("rb") as stream:
            while data := stream.read(CHUNK):
                name = f"chunks/{digest}/{len(parts):03d}.bin"
                destination = target / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(data)
                parts.append("/" + name)
        manifest["/" + source.name] = {
            "parts": parts, "size": source.stat().st_size, "sha256": digest,
            "type": "application/wasm" if source.suffix == ".wasm" else "application/octet-stream",
        }
    for row in index["packs"].values():
        destination = target / row["url"]
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(SOURCE / row["url"], destination)
    shutil.copy2(SOURCE / "web_packs.json", target / "web_packs.json")
    worker = (ROOT / "web/cloudflare-worker.js").read_text()
    (target / "_worker.js").write_text("const FILES = " + json.dumps(manifest) + ";\n" + worker)
    (target / "_routes.json").write_text(json.dumps({"version": 1, "include": list(manifest), "exclude": []}))
    # Disjoint rules: Pages joins repeated headers from overlapping matches.
    (target / "_headers").write_text("/\n  Cache-Control: public, max-age=0, must-revalidate\n/index*\n  Cache-Control: public, max-age=0, must-revalidate\n/web_packs.json\n  Cache-Control: public, max-age=0, must-revalidate\n/chunks/*\n  Cache-Control: public, max-age=31536000, immutable\n/packs/*\n  Cache-Control: public, max-age=31536000, immutable\n")
    (target / "404.html").write_text("Not found")
    assert TARGET.resolve() == (ROOT.resolve() / "build/cloudflare") and not TARGET.is_symlink()
    if TARGET.exists(): shutil.rmtree(TARGET)
    staging.replace(TARGET)
    (ROOT / "build/cloudflare_manifest.json").write_text(json.dumps(manifest, indent=2))
    print(f"Cloudflare staged: {TARGET}; {len(manifest)} streamed files, {len(index['packs'])} immutable packs")


if __name__ == "__main__":
    main()
