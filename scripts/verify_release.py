#!/usr/bin/env python3
"""Verify the exact graphics and runtime files shipped in this release."""
from pathlib import Path
import hashlib,json
base=Path(__file__).resolve().parent
manifest=json.loads((base/'shared-runtime.json').read_text())
files={base/'runtime'/manifest['executable']:manifest['sha256']}
for component in manifest['components'].values():
 for filename,sha in component['files'].items():files[base/'runtime'/component['directory']/filename]=sha
profiles=json.loads((base/'profiles.json').read_text())
for spec in profiles.values():
 if spec.get('driverRecipe'):
  recipe=json.loads((base/'recipes'/spec['driverRecipe']).read_text())
  files[base/spec['driverDirectory']/'libMoltenVK.dylib']=recipe['driver_sha256']
for p,sha in files.items():
 if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest()!=sha:raise SystemExit('Release verification failed: '+str(p.relative_to(base)))
print('Release verified: runtime and graphics libraries match.')
