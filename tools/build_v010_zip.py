#!/usr/bin/env python3
"""Full Godot project archive: imported .godot included, Git history excluded."""
from pathlib import Path
import hashlib
import zipfile
root = Path(__file__).resolve().parents[1]
output = root.parent / 'Сонная стройка v0.10.zip'
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for path in sorted(root.rglob('*')):
        relative = path.relative_to(root)
        if path.is_file() and '.git' not in relative.parts:
            archive.write(path, 'Сонная стройка v0.10/' + relative.as_posix())
with zipfile.ZipFile(output) as archive:
    assert archive.testzip() is None
    assert any('/.godot/imported/' in name for name in archive.namelist())
    assert not any('/.git/' in name for name in archive.namelist())
    print('ZIP', output, 'files', len(archive.namelist()), 'bytes', output.stat().st_size)
print('SHA256', hashlib.file_digest(output.open('rb'), 'sha256').hexdigest())
