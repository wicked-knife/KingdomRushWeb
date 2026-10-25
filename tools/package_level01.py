"""Package the verified Web export for a standalone local HTTP playtest."""
from pathlib import Path
import hashlib, json, zipfile

ROOT=Path(__file__).resolve().parents[1]

def package():
    folder=ROOT/"build/web"
    report=json.loads((folder/"pack_files.json").read_text(encoding="utf-8"))
    assert report["passed"],"Run tools/web_bootstrap.py export successfully first"
    (folder/"start_server.cmd").write_text('@echo off\ncd /d "%~dp0"\necho Open http://127.0.0.1:8060/ in your browser.\necho Keep this window open. Press Ctrl+C to stop.\npython -m http.server 8060 --bind 127.0.0.1\npause\n',encoding="ascii")
    (folder/"README.txt").write_text("Kingdom Rush Dove - First campaign playtest\nSource: Dove 2.1.0.2 / e29ece82\n\n1. Extract this whole folder.\n2. Run start_server.cmd (Python 3 required), or serve this folder with any HTTP server.\n3. Open http://127.0.0.1:8060/ . Do not open index.html with file:// .\n4. Click Start, confirm the tutorials, build towers, then start wave 1.\n\nControls: left click to select/build/cast; right click to cancel; Esc to close/pause;\nClick a soldier/enemy to inspect live stats. Click a sheep 8 times to pop it.\n1 = fire rain, 2 = reinforcements, Space = next wave. Skills unlock after wave 3/7 tutorials.\n\nNormal difficulty, no hero or technology, 20 lives, 270 gold, 7 waves.\nBrowser gameplay, audio unlocking and background-tab behavior require manual acceptance.\nCompatibility renderer / single-thread Web / no COOP or COEP required.\n",encoding="utf-8")
    files=[p for p in sorted(folder.iterdir()) if p.is_file() and p.suffix in {".html",".js",".wasm",".pck",".png",".json",".txt",".cmd"}]
    output=ROOT/"build/KingdomRush-Level01-Web.zip"
    with zipfile.ZipFile(output,"w",compression=zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
        for path in files: archive.write(path,path.name)
    result={"passed":True,"source_commit":"e29ece82939fd73fb69bfc4b469d484a72e4dfd2","browser_tested":False,"pck_isolated_check":True,"pck_files":len(report["files"]),"bundle":str(output.relative_to(ROOT)),"bytes":output.stat().st_size,"sha256":hashlib.sha256(output.read_bytes()).hexdigest(),"web_files":{p.name:{"bytes":p.stat().st_size,"sha256":hashlib.sha256(p.read_bytes()).hexdigest()} for p in files}}
    (ROOT/"reports/level01_web.json").write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({k:v for k,v in result.items() if k!="web_files"}))

if __name__=="__main__": package()
