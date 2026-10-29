"""Package the menu, KR1 map and all registered level/mode entries for manual Web acceptance."""
from pathlib import Path
import hashlib
import json
import zipfile
from campaign_content import level_ids, combinations
from dove_source import BASE, VERSION

ROOT = Path(__file__).resolve().parents[1]


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def package():
    folder = ROOT / "build/web"
    receipt = json.loads((folder / "export_receipt.json").read_text(encoding="utf-8"))
    if not receipt.get("export_succeeded") or receipt.get("pck_sha256") != sha256(folder / "index.pck"):
        raise RuntimeError("Run tools/web_bootstrap.py export successfully before packaging this build")
    if not receipt.get('feedback_acceptance',{}).get('passed'):
        raise RuntimeError('Current feedback acceptance is required before packaging')
    for path,expected in receipt.get('feedback_report_sha256',{}).items():
        if sha256(ROOT/path)!=expected:raise RuntimeError('Feedback report changed after export: '+path)
    last = max(level_ids())
    count = len(combinations())
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
        f"Kingdom Rush Web - KR1 levels 1-{last} campaign and challenges playtest\n"
        f"Source: Dove {VERSION} / {BASE[:8]}\n\n"
        "1. Extract this whole folder.\n"
        "2. Run start_server.cmd (Python 3 required), or serve this folder with any HTTP server.\n"
        "3. Open http://127.0.0.1:8060/ . Do not open index.html with file:// .\n"
        "4. Click Start, choose one of three save slots, select the first flag, then enter battle.\n"
        "5. Confirm tutorials, build towers and click the skull at the entrance to start wave 1.\n"
        "6. Victory saves last_victory; return to the map to commit best stars and unlock the next flag.\n"
        f"Levels 1-{last} campaign, Heroic and Iron entries are enabled on normal difficulty ({count} combinations).\n"
        "Earn three campaign stars on a level to enter its challenges. Each challenge starts with one life.\n"
        "Heroic: 6 waves; Iron: 1 wave. First completion of each challenge grants one star.\n"
        f"Campaign three stars plus both challenges total {len(level_ids()) * 5} stars. Level {last + 1} is a preview.\n"
        "Heroic gold (levels 1-7): 230/310/400/750/1000/1200/1000. Iron: 360/275/660/1500/1500/800/1200.\n"
        "Iron tower bans: L1 archer+mage; L2 barracks; L3 artillery; L4 mage+artillery; L5 barracks.\n"
        "L5 Iron has 3 free tier-3 archers and 2 elf ruins; camp repair/recruit/skills remain available.\n"
        "Level 2: 240 gold, 7 waves, 7 tower sites. Level 3: 330 gold, 11 waves, 12 sites, two lanes.\n"
        "All four tower types can upgrade to level 2 in campaigns 2 and 3, and level 3 in campaign 4.\n"
        "Level 4: 520 gold, 13 waves, 15 tower sites, two lanes, bandits and brigands.\n"
        "Level 5: 700 gold, 15 waves, 14 sites (free tier-3 archer and elf ruins), 242 wave enemies plus hatched spiders.\n"
        "Level 5 opens Rangers (230 from tier-3 archers), Poison Arrows and Wrath of the Forest.\n"
        "Elf camp: repair for 190; recruit up to 4 paid slots at 100 each. Fallen elves refill automatically.\n"
        "Bleed: 100/100/100; Cripple: 200/125/125. Hiring costs are excluded from sale refunds.\n"
        "Level 6: 700 gold, 17 waves, 15 sites, 7 permanent royal guards, flying gargoyles, shadow archers and Juggernaut.\n"
        "Paladins (185 from barracks3): Healing Light, Holy Strike, Shield. Arcane (290 from mage3): Death Ray, Teleport.\n"
        "Level 6 Iron has 2 free mage3 towers; only barracks can be newly built. Heroes do not enter battle.\n"
        "Level 7: 700 gold, 16 waves, snow, two tunnels, regenerating trolls and white wolves.\n"
        "Tier-3 archers offer Ranger and Musketeer branches at source menu positions, with separate saved locks.\n"
        "Musketeer: alternating shooters, Sniper/Headshot and six-shell Shrapnel. Victory/map settlement unlocks it permanently.\n"
        "Revisiting stages 4-6 includes both branches where source restrictions and your save allow them.\n"
        "Level 7 Iron: 3 free tier-2 barracks; building barracks and artillery is forbidden.\n"
        "Default technology scheme 1: six branches and 36 upgrades, purchased with settled stars on the map.\n"
        "Click a higher rank to buy missing prerequisites, or a purchased rank to refund it and later ranks.\n"
        "Purchases save immediately. Undo restores this opening's levels; Reset clears levels and rebases Undo.\n"
        "Each mode caps effective technology without changing purchased ranks. Other schemes remain preserved and block play.\n"
        "Three independent local save slots; volume settings remain global.\n"
        "Hero room: browse 79 heroes, view computed skills, select up to two unlocked heroes.\n"
        "Completing level 1 unlocks 12 heroes; selecting a third replaces slot two.\n"
        "Selections save per slot. Heroes do not enter battle in this playtest.\n"
        "Tab cycles selected heroes; Done, Esc or right click closes the hero room.\n"
        "Three unified Dove JSON slots are created from the source template.\n"
        "A defeat after restarting from victory discards that unsettled victory; settled best scores remain.\n\n"
        "Map: screen edges/wheel = pan, Shift+wheel = horizontal pan; touch drag/pinch = pan/zoom.\n"
        "Controls: left click to select/build/cast; right click to cancel; Esc to close/pause.\n"
        "Wave icons appear at active entrances; hover for enemy counts and the route. Click once to start wave 1.\n"
        "Double-click the same icon to call later waves early. Space remains the next-wave shortcut.\n"
        "The timer ring fills until automatic release; either entrance sends the whole dual-path wave.\n"
        "Early-wave rewards animate +gold at the gold counter and -seconds above cooling skills.\n"
        "Click a soldier/enemy to inspect live stats. Click a sheep 8 times to pop it.\n"
        "1 = fire rain, 2 = reinforcements, Space = next wave. Skills unlock after wave 3/7 tutorials in level 1.\n"
        "In all challenges and campaigns 2-7 both skills unlock when wave 1 is sent; neither can be used during setup.\n"
        "Click enemy alerts for information.\n\n"
        "Feedback repairs: tower introductions, grass/snow hover, technology/map stars and colored current-to-next skill values.\n"
        "Cannon targeting/flight and preplaced guard interception follow the frozen Dove source; no difficulty changes.\n\n"
        "Follow-up: source green range/rally artwork, sale removes garrisons without corpses, ordinary bombs use source default 144 Hz integration.\n"
        "Arcane teleport cast animation is complete; moving/dying preplaced guards no longer leave static layout copies.\n\n"
        "Normal difficulty, no hero combat. Campaigns start with 20 lives, challenges with 1.\n"
        "Campaign level 1: 270 gold, 7 waves.\n"
        + ("Debug build: click DEV or press F8 in battle. +10000 gold / +100 lives / skip current wave.\n"
           "Debug victories save normally; skip preserves wave 3/7 teaching confirmations.\n" if debug else "Release build: developer commands are disabled.\n")
        + ("The isolated PCK check passed; browser acceptance is manual.\n" if checked else
           "Web validation was not run for this delivery; browser acceptance is manual.\n")
        + "Challenge acceptance: Dove configuration and functionality; complete victory recordings are optional.\n"
        + (f"Supplementary verified challenge victory recordings: {len(receipt.get('challenge_replays_verified', []))}/{len(level_ids()) * 2}.\n" if receipt.get("challenge_replays_run", False) else
           "Complete victory recordings were not run by the default configuration/functionality check.\n")
        + ("All challenge logic acceptance checks passed.\n" if receipt.get("challenge_validation_passed", False) else
           "Challenge configuration/functionality checks have not passed; see the report.\n")
        + f"Unrecorded modes (optional, non-blocking; 2=Heroic, 3=Iron): {', '.join(receipt.get('challenge_pending_replays', [])) or 'none'}.\n"
        + "Check gameplay, audio unlocking, background-tab behavior and persistence in your browser.\n"
        "Compatibility renderer / single-thread Web / no COOP or COEP required.\n",
        encoding="utf-8",
    )
    # Only include this export's generated runtime and delivery metadata, not old reports.
    files = [p for p in sorted(folder.glob("index.*")) if p.is_file() and p.suffix in {".html", ".js", ".wasm", ".pck", ".png"}]
    files += [folder / name for name in ("export_receipt.json", "README.txt", "start_server.cmd")]
    if checked:
        files.append(folder / "pack_files.json")
    output = ROOT / ("build/KingdomRush-KR1-Playtest-Debug-Web.zip" if debug else f"build/KingdomRush-KR1-Levels01-{last:02d}-Web.zip")
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in files:
            archive.write(path, path.name)
    result = {
        "package_created": True,
        "source_commit": "1a863df00b08f6bf1018ae0b0e7e4e106b939082",
        "content_catalog_sha256": receipt.get("content_catalog_sha256"),
        "browser_tested": False,
        "build_type": receipt.get("build_type", "release"),
        "developer_menu": debug,
        "includes_hero_room": receipt.get("includes_hero_room", False),
        "playable_levels": receipt.get("playable_levels", []),
        "playable_modes": receipt.get("playable_modes", []),
        "playable_combinations": receipt.get("playable_combinations", []),
        "challenge_validation_passed": receipt.get("challenge_validation_passed", False),
        "challenge_acceptance_basis": receipt.get("challenge_acceptance_basis"),
        "challenge_victory_replays_required": False,
        "challenge_replays_run": receipt.get("challenge_replays_run", False),
        "challenge_replay_files": receipt.get("challenge_replay_files", []),
        "challenge_pending_replays": receipt.get("challenge_pending_replays", []),
        "challenge_replays_verified": receipt.get("challenge_replays_verified", []),
        "pck_isolated_check": checked,
        "battle_ui_acceptance": receipt.get("battle_ui_acceptance", {}),
        "default_technology_acceptance": receipt.get("default_technology_acceptance", {}),
        "feedback_acceptance": receipt.get("feedback_acceptance", {}),
        "feedback_report_sha256": receipt.get("feedback_report_sha256", {}),
        "seventh_acceptance": receipt.get("seventh_acceptance", {}),
        "validation_report_sha256": receipt.get("validation_report_sha256", {}),
        "technology_scheme": receipt.get("technology_scheme"),
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
