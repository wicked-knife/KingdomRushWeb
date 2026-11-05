"""Collect current split-pack, native-window, HTTP and release evidence."""
import json
from pathlib import Path
import zipfile

from web_packs import ROOT, digest_file


def read(path):
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


def main():
    receipt = read("build/web/export_receipt.json")
    index = read("build/web/web_packs.json")
    report = read("build/web/pack_report.json")
    union = read("build/web/pack_files.json")
    downloads = read("reports/content_downloads.json")
    native = read("output/web_packs_native/report.json")
    cloudflare = read("build/cloudflare_verification.json")
    package = read("reports/map_kr1_web.json")
    assert receipt["pck_isolated_check"] and union["passed"] and report == receipt["pack_report"]
    assert digest_file(ROOT / "build/web/index.pck") == receipt["pck_sha256"] == native["boot_sha256"]
    assert digest_file(ROOT / "build/web/web_packs.json") == receipt["packs_manifest_sha256"] == native["manifest_sha256"] == cloudflare["manifest_sha256"]
    assert downloads["passed"] and native["passed"] and cloudflare["passed"]
    for path, expected in downloads["source_hashes"].items():
        assert digest_file(ROOT / path) == expected, ("stale HTTP acceptance", path)
    for path, expected in receipt["current_source_sha256"].items():
        if path == "tools/package_level01.py": continue
        assert digest_file(ROOT / path) == expected, ("export input changed", path)
    assert digest_file(ROOT / "tests/web_packs_native.gd") == native["test_sha256"]
    assert cloudflare["immutable_packs"] == len(index["packs"])
    assert digest_file(ROOT / "build/cloudflare/_worker.js") == cloudflare["worker_sha256"]
    assert digest_file(ROOT / "build/cloudflare/_headers") == cloudflare["headers_sha256"]
    assert digest_file(ROOT / "tools/package_level01.py") == package["packager_sha256"]
    archive = ROOT / package["bundle"]
    assert digest_file(archive) == package["sha256"]
    with zipfile.ZipFile(archive) as zipped:
        assert set(zipped.namelist()) == set(package["web_files"])
        assert zipped.testzip() is None
    paths = ["tools/web_packs.py", "tools/web_bootstrap.py", "tools/package_level01.py",
             "tools/prepare_cloudflare.py", "tools/verify_cloudflare.mjs", "tools/check_web_packs_native.py",
             "tools/verify_web_packs_delivery.py", "tests/test_web_packs.py", "web/shell.html",
             "scripts/app_root.gd", "scripts/services/hero_loader.gd", *downloads["source_hashes"]]
    result = {
        "passed": True,
        "original_pck_bytes": report["original_bytes"], "startup_pck_bytes": report["boot_bytes"],
        "total_pck_bytes": report["total_bytes"], "saved_bytes": report["saved_bytes"],
        "startup_reduction_percent": round(100 * (1 - report["boot_bytes"] / report["original_bytes"]), 2),
        "deferred_packs": len(index["packs"]), "resource_paths_compared": report["verification"]["resource_paths"],
        "complete_union_check": {"passed": union["passed"], "mode_configurations": union["mode_combinations_checked"]},
        "download_check": {key: downloads[key] for key in ("passed", "checks", "independent_scenarios")},
        "native_check": {key: native[key] for key in ("passed", "checks", "independent_scenarios", "native_input", "native_audio_playback")},
        "cloudflare_check": {key: cloudflare[key] for key in ("passed", "immutable_packs", "streamed_files")},
        "boot_sha256": receipt["pck_sha256"], "manifest_sha256": receipt["packs_manifest_sha256"],
        "package": {"path": archive.relative_to(ROOT).as_posix(), "bytes": archive.stat().st_size, "sha256": package["sha256"]},
        "source_hashes": {path: digest_file(ROOT / path) for path in sorted(set(paths))},
        "browser_tested": False, "deployed": False, "full_victory_replays_run": False,
    }
    (ROOT / "reports/web_packs_delivery.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: value for key, value in result.items() if key != "source_hashes"}, ensure_ascii=False))


if __name__ == "__main__": main()
