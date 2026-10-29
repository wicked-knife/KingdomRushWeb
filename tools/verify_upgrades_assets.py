"""Default technology closure and fail-closed publication probes."""
import copy
import hashlib
import json
from pathlib import Path
from upgrades_contract import validate_technology_dependencies, validate_technology_resources

ROOT = Path(__file__).resolve().parents[1]


def read(path): return json.loads((ROOT / path).read_text(encoding="utf-8"))


def verify():
    from campaign_content import level_ids
    definitions = [f"level{i:02}" for i in level_ids()] + ["ranger_arena"]
    hashes, rows, probes = {}, [], []
    for name in definitions:
        data, animations, atlas, sounds = [read(f"data/{name}/{part}.json") for part in ("definition", "animations", "atlas", "sounds")]
        validate_technology_dependencies(data)
        validate_technology_resources(data, animations["animations"], atlas, sounds)
        rows.append({"content":name,"templates":len(data["templates"]),"closed":True})
        for file in (ROOT / f"data/{name}").iterdir():
            if file.suffix in (".json", ".png"): hashes[file.relative_to(ROOT).as_posix()] = hashlib.sha256(file.read_bytes()).hexdigest()
    data, animations, atlas, sounds = [read(f"data/level06/{part}.json") for part in ("definition", "animations", "atlas", "sounds")]
    for kind, missing in [("template","mod_blood_elves"),("template","re_legionnaire_ranged"),("template","fx_bleeding"),("template","spear_legionnaire"),("animation","re_legionnaire_ranged_1_ranged_attack"),("frame","decal_spear"),("sound","AxeSound")]:
        d,a,f,s = copy.deepcopy((data, animations["animations"], atlas, sounds))
        owner = {"template":d["templates"],"animation":a,"frame":f["lookup"],"sound":s}[kind]
        del owner[missing]
        try:
            validate_technology_dependencies(d); validate_technology_resources(d,a,f,s)
        except ValueError as error:
            reason = str(error)
            assert "technology " in reason and missing in reason, reason
            probes.append({"kind":kind,"missing":missing,"rejected":True,"reason":reason})
        else: raise AssertionError(f"Publication accepted missing {kind}: {missing}")
    for file in ["data/upgrades/definition.json","tools/upgrades_contract.py","tools/prepare_upgrades.py","tools/prepare_level01.py","tools/level01_export/main.lua"]:
        hashes[file] = hashlib.sha256((ROOT / file).read_bytes()).hexdigest()
    result={"passed":True,"contents":rows,"failure_probes":probes,"source_hashes":hashes}
    (ROOT / "reports/upgrades_assets.json").write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"passed":True,"contents":len(rows),"failure_probes":probes},ensure_ascii=False))


if __name__ == "__main__": verify()
