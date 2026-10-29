"""Execute pinned Dove wave, Musketeer, shotgun, tunnel and regen coroutines."""
import json
import os
import subprocess
from pathlib import Path
from dove_source import verify, provenance
from import_dove_assets import decode_animations

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path('D:/projects/KingdomRushDove')

if __name__ == '__main__':
    verify(SOURCE)
    data = json.loads((ROOT / 'data/level07/definition.json').read_text(encoding='utf-8'))
    data['animations'] = decode_animations((SOURCE / 'kr1/data/game_animations.bin').read_bytes())['animations']
    inputs = ['kr1/tower_scripts.lua', 'kr1/archer_towers.lua', 'all/scripts.lua', 'all/utils.lua',
              'all/seek.lua', 'all/systems/wave_spawn.lua', 'kr1/data/game_animations.bin',
              'kr1/data/levels/level07_data.lua', *[f'kr1/data/waves/level07_waves_{m}.lua' for m in ('campaign','heroic','iron')]]
    data['provenance'] = provenance(SOURCE, inputs)
    (ROOT / 'output/level07_reference_input.json').write_text(json.dumps(data), encoding='utf-8')
    subprocess.run(['D:/王国保卫战Dove版/love.exe', str(ROOT / 'tools/level07_reference')],
                   env=dict(os.environ, DOVE_SOURCE_DIR=str(SOURCE), DOVE_CATALOG=str(ROOT / 'data/campaign_content.json'),
                            DOVE_PROJECT=str(ROOT), DOVE_REFERENCE_OUTPUT=str(ROOT / 'tests/fixtures/level07_source.json')),
                   check=True, timeout=45)
    result = json.loads((ROOT / 'tests/fixtures/level07_source.json').read_text(encoding='utf-8'))
    print({k: len(result[k]) for k in ('modes','towers','shotguns','regen','tunnels')})
