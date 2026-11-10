#!/usr/bin/env python3
"""Generate the fixture using the actual original serializer, then remove temporary source."""
from pathlib import Path
import subprocess
root=Path(__file__).resolve().parents[1]
old=root/'tools/_legacy_game_state_v091.gd'
try:
    old.write_bytes(subprocess.check_output(['git','show','89cbb0d807041022accddd5a8837c3be90720359:scripts/game_state.gd'],cwd=root))
    subprocess.run(['/home/box/godot/godot','--headless','--path',str(root),'--script','res://tools/make_v091_fixture.gd'],check=True,timeout=30)
finally:
    old.unlink(missing_ok=True)
    old.with_suffix('.gd.uid').unlink(missing_ok=True)
