"""Combine current Git metadata with installed media, then update the asset snapshot."""
import argparse
import io
import os
import subprocess
import tarfile
from pathlib import Path
from dove_source import BASE, ROOT, verify
from import_dove_assets import Migration, write_summary


def sync(source, media):
    verify(source)
    stage = ROOT / 'output' / ('dove_assets_' + BASE[:12])
    stage.mkdir(parents=True, exist_ok=True)
    # Archive first, and never overwrite a hard link to installed media.
    archive = subprocess.check_output(['git', '-C', str(source), 'archive', 'HEAD'])
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        for member in tar.getmembers():
            target = stage / member.name
            assert target.resolve().is_relative_to(stage.resolve())
            if member.isfile() and target.exists():
                target.unlink()
        tar.extractall(stage, filter='data')
    for folder in ['_assets', 'kr1/data', 'kr1-desktop/data', 'all-desktop/data']:
        for original in (media / folder).rglob('*'):
            if not original.is_file() or original.suffix.lower() in {'.lua', '.exe', '.dll', '.bat', '.lnk'}:
                continue
            target = stage / original.relative_to(media)
            if not target.exists():
                target.parent.mkdir(parents=True, exist_ok=True)
                os.link(original, target)
    (stage / 'current_version_commit_hash.txt').write_text(BASE + '\n', encoding='utf-8')
    Migration(stage, ROOT, source).run()
    write_summary(ROOT)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path('D:/projects/KingdomRushDove'))
    parser.add_argument('--media', type=Path, default=Path('D:/王国保卫战Dove版/KingdomRushDove'))
    args = parser.parse_args()
    sync(args.source.resolve(), args.media.resolve())
