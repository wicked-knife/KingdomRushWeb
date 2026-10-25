"""Package the menu, KR1 map and first campaign export for manual Web acceptance."""
from pathlib import Path
import hashlib
import json
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def package():
    folder = ROOT / "build/web"
    receipt = json.loads((folder / "export_receipt.json").read_text(encoding="utf-8"))
    if not receipt.get("export_succeeded") or receipt.get("pck_sha256") != sha256(folder / "index.pck"):
        raise RuntimeError("Run tools/web_bootstrap.py export successfully before packaging this build")
    debug = receipt.get("developer_menu", False)
    checked = receipt.get("pck_isolated_check", False)
    report = json.loads((folder / "pack_files.json").read_text(encoding="utf-8")) if checked else None
    if checked and not report.get("passed"):
        raise RuntimeError("The requested PCK check did not pass")
    (folder / "start_server.cmd").write_text(
        '@echo off\ncd /d "%~dp0"\necho Open http://127.0.0.1:8060/ in your browser.\n'
        'echo Keep this window open. Press Ctrl+C to stop.\npython -m http.server 8060 --bind 127.0.0.1\npause\n',
        encoding="ascii",
    )
    (folder / "README.txt").write_text(
        "Kingdom Rush Web - KR1 map and first campaign playtest\n"
        "Source: Dove 2.1.0.2 / e29ece82\n\n"
        "1. Extract this whole folder.\n"
        "2. Run start_server.cmd (Python 3 required), or serve this folder with any HTTP server.\n"
        "3. Open http://127.0.0.1:8060/ . Do not open index.html with file:// .\n"
        "4. Click Start, choose one of three save slots, select the first flag, then enter battle.\n"
        "5. Confirm tutorials, build towers and start wave 1.\n"
        "6. Victory saves best stars and unlocks the second flag. Return to the map to see it.\n"
        "Only level 1 campaign is playable; other stages and challenges are previews.\n"
        "Three independent local save slots; volume settings remain global.\n"
        "Hero room: browse 79 heroes, view computed skills, select up to two unlocked heroes.\n"
        "Completing level 1 unlocks 12 heroes; selecting a third replaces slot two.\n"
        "Selections save per slot. Heroes do not enter battle in this playtest.\n"
        "Tab cycles selected heroes; Done, Esc or right click closes the hero room.\n"
        "The earlier single campaign save migrates into slot 1 automatically.\n\n"
        "Map: screen edges/wheel = pan, Shift+wheel = horizontal pan; touch drag/pinch = pan/zoom.\n"
        "Controls: left click to select/build/cast; right click to cancel; Esc to close/pause.\n"
        "Click a soldier/enemy to inspect live stats. Click a sheep 8 times to pop it.\n"
        "1 = fire rain, 2 = reinforcements, Space = next wave. Skills unlock after wave 3/7 tutorials.\n\n"
        "Normal difficulty, no hero or technology, 20 lives, 270 gold, 7 waves.\n"
        + ("Debug build: click DEV or press F8 in battle. +10000 gold / +100 lives / skip current wave.\n"
           "Debug victories save normally; skip preserves wave 3/7 teaching confirmations.\n" if debug else "Release build: developer commands are disabled.\n")
        + ("The isolated PCK check passed; browser acceptance is manual.\n" if checked else
           "Web validation was not run for this delivery; browser acceptance is manual.\n")
        + "Check gameplay, audio unlocking, background-tab behavior and persistence in your browser.\n"
        "Compatibility renderer / single-thread Web / no COOP or COEP required.\n",
        encoding="utf-8",
    )
    # Only include this export's generated runtime and delivery metadata, not old reports.
    files = [p for p in sorted(folder.glob("index.*")) if p.is_file() and p.suffix in {".html", ".js", ".wasm", ".pck", ".png"}]
    files += [folder / name for name in ("export_receipt.json", "README.txt", "start_server.cmd")]
    if checked:
        files.append(folder / "pack_files.json")
    output = ROOT / ("build/KingdomRush-KR1-Playtest-Debug-Web.zip" if debug else "build/KingdomRush-KR1-Map-Web.zip")
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in files:
            archive.write(path, path.name)
    result = {
        "package_created": True,
        "source_commit": "e29ece82939fd73fb69bfc4b469d484a72e4dfd2",
        "browser_tested": False,
        "build_type": receipt.get("build_type", "release"),
        "developer_menu": debug,
        "includes_hero_room": receipt.get("includes_hero_room", False),
        "pck_isolated_check": checked,
        "pck_files": len(report["files"]) if checked else None,
        "bundle": str(output.relative_to(ROOT)),
        "bytes": output.stat().st_size,
        "sha256": sha256(output),
        "web_files": {p.name: {"bytes": p.stat().st_size, "sha256": sha256(p)} for p in files},
    }
    (ROOT / "reports/map_kr1_web.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k != "web_files"}))


if __name__ == "__main__":
    package()
