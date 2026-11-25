"""Stage an existing Godot Web export for Cloudflare Pages (25 MiB per asset) with Brotli/Gzip precompression."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
from web_packs import digest_file, LIMIT

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "build/web"
TARGET = ROOT / "build/cloudflare"
CHUNK = 24 * 1024 * 1024
PRECOMPRESS_MIN_SAVINGS = 128 * 1024


def write_chunks(source: Path, target_dir: Path, digest: str, prefix: str = "") -> list[str]:
    parts = []
    with source.open("rb") as stream:
        while data := stream.read(CHUNK):
            name = f"chunks/{digest}/{prefix}{len(parts):03d}.bin"
            destination = target_dir / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
            parts.append("/" + name)
    return parts


def build_precompressed(candidates: list[dict], staging: Path) -> dict[str, dict]:
    """Use Node's native zlib (Brotli-11 & Gzip-9) to precompress eligible files into <=24 MiB chunks."""
    if not candidates:
        return {}
    job_file = staging / "_precompress_jobs.json"
    out_file = staging / "_precompress_out.json"
    script_file = staging / "_precompress.mjs"
    job_file.write_text(json.dumps(candidates), encoding="utf-8")
    script = """
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import crypto from 'node:crypto';
const [jobsPath, outPath, stagingDir, chunkLimit] = process.argv.slice(2);
const jobs = JSON.parse(fs.readFileSync(jobsPath, 'utf8'));
const limit = Number(chunkLimit);
const result = {};
for (const job of jobs) {
  const raw = fs.readFileSync(job.source);
  const entry = { encodings: {} };
  for (const [enc, fn] of [
    ['br', buf => zlib.brotliCompressSync(buf, { params: { [zlib.constants.BROTLI_PARAM_QUALITY]: 11 } })],
    ['gzip', buf => zlib.gzipSync(buf, { level: 9 })],
  ]) {
    const compressed = fn(raw);
    if (!job.force && (raw.length - compressed.length < 131072 || compressed.length > raw.length * 0.95)) continue;
    const sha256 = crypto.createHash('sha256').update(compressed).digest('hex');
    const parts = [];
    for (let offset = 0, idx = 0; offset < compressed.length; offset += limit, idx++) {
      const slice = compressed.subarray(offset, offset + limit);
      const rel = `chunks/${job.sha256}/${enc}_${String(idx).padStart(3, '0')}.bin`;
      const dst = path.join(stagingDir, rel);
      fs.mkdirSync(path.dirname(dst), { recursive: true });
      fs.writeFileSync(dst, slice);
      parts.push('/' + rel);
    }
    entry.encodings[enc] = { parts, size: compressed.length, sha256 };
  }
  if (Object.keys(entry.encodings).length) result[job.route] = entry;
}
fs.writeFileSync(outPath, JSON.stringify(result));
"""
    script_file.write_text(script, encoding="utf-8")
    subprocess.run(["node", str(script_file), str(job_file), str(out_file), str(staging), str(CHUNK)], check=True)
    results = json.loads(out_file.read_text(encoding="utf-8"))
    job_file.unlink(missing_ok=True)
    out_file.unlink(missing_ok=True)
    script_file.unlink(missing_ok=True)
    return results


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
    precompress_jobs = []
    boot_files = {}

    for source in SOURCE.iterdir():
        if source.suffix not in {".html", ".js", ".png", ".pck", ".wasm"}:
            continue
        if source.suffix in {".wasm", ".pck"}:
            digest = digest_file(source)
            size = source.stat().st_size
            route = "/" + source.name
            mime = "application/wasm" if source.suffix == ".wasm" else "application/octet-stream"
            if size > CHUNK:
                parts = write_chunks(source, target, digest)
            else:
                shutil.copy2(source, target / source.name)
                parts = [route]
            boot_files[route] = {
                "parts": parts,
                "size": size,
                "sha256": digest,
                "type": mime,
                "cache_control": "public, max-age=0, must-revalidate",
            }
            precompress_jobs.append({"route": route, "source": str(source), "sha256": digest, "force": True})
        else:
            shutil.copy2(source, target / source.name)

    for row in index["packs"].values():
        src_pack = SOURCE / row["url"]
        destination = target / row["url"]
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src_pack, destination)
        route = "/" + row["url"]
        boot_files[route] = {
            "parts": [route],
            "size": row["size"],
            "sha256": row["sha256"],
            "type": "application/octet-stream",
            "cache_control": "public, max-age=31536000, immutable",
        }
        precompress_jobs.append({"route": route, "source": str(src_pack), "sha256": row["sha256"], "force": False})

    precompressed = build_precompressed(precompress_jobs, staging)
    for route, entry in boot_files.items():
        comp = precompressed.get(route, {}).get("encodings", {})
        # Only route through Worker if the file exceeds 24 MiB or has meaningful precompressed variants.
        if entry["size"] > CHUNK or comp:
            entry["encodings"] = comp
            manifest[route] = entry

    shutil.copy2(SOURCE / "web_packs.json", target / "web_packs.json")
    worker = (ROOT / "web/cloudflare-worker.js").read_text()
    (target / "_worker.js").write_text("const FILES = " + json.dumps(manifest) + ";\n" + worker)
    (target / "_routes.json").write_text(json.dumps({"version": 1, "include": list(manifest), "exclude": []}))
    # Disjoint rules: Pages joins repeated headers from overlapping matches.
    (target / "_headers").write_text(
        "/\n  Cache-Control: public, max-age=0, must-revalidate\n"
        "/index*\n  Cache-Control: public, max-age=0, must-revalidate\n"
        "/web_packs.json\n  Cache-Control: public, max-age=0, must-revalidate\n"
        "/chunks/*\n  Cache-Control: public, max-age=31536000, immutable\n"
        "/packs/*\n  Cache-Control: public, max-age=31536000, immutable\n"
    )
    (target / "404.html").write_text("Not found")
    assert TARGET.resolve() == (ROOT.resolve() / "build/cloudflare") and not TARGET.is_symlink()
    if TARGET.exists():
        shutil.rmtree(TARGET)
    staging.replace(TARGET)
    (ROOT / "build/cloudflare_manifest.json").write_text(json.dumps(manifest, indent=2))
    br_bytes = sum(
        (m.get("encodings", {}).get("br", {}).get("size", m["size"]))
        for m in manifest.values()
    )
    raw_bytes = sum(m["size"] for m in manifest.values())
    print(f"Cloudflare staged: {TARGET}; {len(manifest)} worker-managed routes (raw {raw_bytes/1048576:.2f} MiB -> br {br_bytes/1048576:.2f} MiB), {len(index['packs'])} immutable packs")


if __name__ == "__main__":
    main()
