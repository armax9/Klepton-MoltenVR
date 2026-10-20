"""Engine-level APK routing. Package-specific recipes always take precedence.
Detection is structural: folder names never select an engine or a game patch.
"""
ARM64='lib/arm64-v8a/'
def detect(names, spec=None):
    names=set(names);spec=spec or {}
    has=lambda lib:ARM64+lib+'.so' in names
    candidates=[]
    if has('libunity') and has('libmain'):candidates.append(('Unity','unity','libmain'))
    if has('libUnreal'):candidates.append(('Unreal Engine 5','unreal','libUnreal'))
    if has('libUE4'):candidates.append(('Unreal Engine 4','unreal','libUE4'))
    entry=spec.get('entry')
    if entry and has(entry):
        chosen=next((x for x in candidates if x[2]==entry),None)
        if chosen is None and spec.get('kind')=='KL_GUEST_UNITY':chosen=('Unity','unity',entry)
        if chosen is None:chosen=('Custom engine','custom',entry)
        engine,family,entry=chosen
        return dict(engine=engine,engineFamily=family,entry=entry,supported=True,profileSource='game',reason='Package-specific profile')
    if len(candidates)==1:
        engine,family,entry=candidates[0]
        return dict(engine=engine,engineFamily=family,entry=entry,supported=True,profileSource='game' if spec.get('runtimeOverrides') else 'engine',reason='Package-specific profile' if spec.get('runtimeOverrides') else 'Automatic '+engine+' ARM64 profile')
    if len(candidates)>1:
        return dict(engine='Multiple engines',engineFamily='unknown',supported=False,profileSource='none',reason='Ambiguous engine libraries; a package profile is required')
    engine='Godot' if any(n.startswith(ARM64+'libgodot') for n in names) else 'Unknown engine'
    reason='No ARM64 libraries found' if not any(n.startswith(ARM64) and n.endswith('.so') for n in names) else 'No compatible engine adapter found'
    return dict(engine=engine,engineFamily='unknown',supported=False,profileSource='none',reason=reason)

def defaults(item):
    """Conservative common facilities, without title-specific binary patches."""
    env={'KL_MOLTENVR_COMPOSITE_PANELS':'1'}
    if item['profileSource']=='engine' and item['engineFamily']=='unreal':
        env['KL_GUEST_OBB']=item['obb']
    return env
