#!/usr/bin/env python3
import os, sys, json, zipfile, hashlib, pathlib
import xml.etree.ElementTree as ET
from apk_manifest import metadata
from engine_profiles import detect, defaults
from runtime_policy import configure_runtime
BASE=pathlib.Path(__file__).resolve().parent
RUNTIME=BASE/"runtime"
PROFILES=json.loads((BASE/'profiles.json').read_text())
def inspect(p, root):
    try:
        with zipfile.ZipFile(p) as z:
            names=set(z.namelist())
            _,meta=metadata(z.read('AndroidManifest.xml'))
        spec=PROFILES.get(meta['package'],{})
        detected=detect(names,spec)
        if spec.get('entry') and detected['profileSource']!='game':
            spec={}  # A changed APK must not inherit an incompatible entry/tree.
        brush=meta['package'] in ('foundation.icosa.openbrush','org.icosa.openbrush')
        # A known package retains its recipe; unknown UE APKs use Android's
        # package OBB path, whereas generic Unity uses Context.getObbDir().
        obb=spec.get('obb','Android/obb/'+meta['package'] if detected['engineFamily']=='unreal' else 'obb')
        return dict(metadata=meta,path=str(p),title=p.parent.name if p.parent!=root else p.stem,
                    verified=bool(spec.get('verified')),tested=bool(spec.get('tested') or spec.get('verified')),verificationSource=spec.get('verificationSource','Gameplay has not been verified.'),
                    profile=spec.get('target','openbrush' if brush else 'game'),tree=spec.get('tree'),kind=spec.get('kind'),obb=obb,
                    status=detected['reason'],**detected)
    except Exception: return None
def scan(root):
    root=pathlib.Path(root).expanduser().resolve(); out=[]
    for folder, dirs, files in os.walk(root):
        dirs[:]=[d for d in dirs if not d.startswith('.') and d not in ('data','build','node_modules')]
        for f in files:
            if f.lower().endswith('.apk'):
                item=inspect(pathlib.Path(folder)/f,root)
                if item:out.append(item)
    return sorted(out,key=lambda x:x['title'].lower())
def prepare(s):
    apk=pathlib.Path(s).resolve(); item=inspect(apk,apk.parent)
    if not item or not item['supported']:raise RuntimeError('This APK has no supported ARM64 runtime profile.')
    key=hashlib.sha256(str(apk).encode()).hexdigest()[:16]; home=pathlib.Path(os.environ.get("APKVR_DATA_DIR",str(pathlib.Path.home()/"Library/Application Support/APK VR Library")))/key; home.mkdir(parents=True,exist_ok=True)
    signature=str(apk.stat().st_size)+':'+str(apk.stat().st_mtime_ns)
    marker=home/'version'; payload=home/'payload'
    if not marker.exists() or marker.read_text()!=signature:
        import shutil
        if payload.exists():shutil.rmtree(payload)
        payload.mkdir()
        with zipfile.ZipFile(apk) as z:
            for info in z.infolist():
                dest=(payload/info.filename).resolve()
                if not dest.is_relative_to(payload.resolve()):raise RuntimeError('Invalid path inside APK')
            z.extractall(payload)
        marker.write_text(signature)
    # Binary XML from a raw ZIP is not readable by Klepton's text manifest parser.
    # Decode only the extracted copy; never modify the source APK.
    with zipfile.ZipFile(apk) as z:
        manifest,meta=metadata(z.read('AndroidManifest.xml'))
    ET.ElementTree(manifest).write(payload/'AndroidManifest.xml',encoding='utf-8',xml_declaration=True)
    (payload/'apktool.yml').write_text('versionInfo:\n  versionCode: '+meta['versionCode']+'\n  versionName: '+meta['versionName'].replace('\n',' ').replace('\r',' ')+'\nsdkInfo:\n  minSdkVersion: '+meta['minSdkVersion']+'\n  targetSdkVersion: '+meta['targetSdkVersion']+'\n')
    session=home/'session'; session.mkdir(exist_ok=True); alias=item.get('tree') or item['profile']
    for name,target in [(alias,payload),(alias+'.apk',apk)]:
        link=session/name
        if link.is_symlink():link.unlink()
        link.symlink_to(target,target_is_directory=target.is_dir())
    userdata=home/'userdata';userdata.mkdir(exist_ok=True)
    # Unity file URLs can resolve /sdcard relative to the native session.
    sdcard=session/'sdcard'
    if not sdcard.exists() and not sdcard.is_symlink():sdcard.symlink_to(userdata.resolve(),target_is_directory=True)
    obbdir=userdata/(item.get('obb') or 'obb');obbdir.mkdir(parents=True,exist_ok=True)
    obbs=sorted(p for p in apk.parent.rglob('*.obb') if p.name.endswith('.'+meta['package']+'.obb'))
    linked=[]
    for source in obbs:
        link=obbdir/source.name
        if link.is_symlink():link.unlink()
        if not link.exists():link.symlink_to(source.resolve())
        linked.append(dict(path=str(link),source=str(source),bytes=source.stat().st_size))
    # Some games ship loose AssetBundles next to their OBB and open the
    # Android external-storage path directly instead of Context.getObbDir().
    external=userdata/'Android'/'obb'/meta['package'];external.mkdir(parents=True,exist_ok=True)
    roots={p.parent for p in obbs}
    roots.update(p for p in apk.parent.rglob(meta['package']) if p.is_dir())
    external_count=0
    for folder in sorted(roots):
        for source in folder.rglob('*'):
            if not source.is_file():continue
            # Both Context.getObbDir() and hard-coded /sdcard/Android/obb
            # must expose the same loose data alongside the expansion files.
            for destination in (external, obbdir):
                target=destination/source.relative_to(folder)
                target.parent.mkdir(parents=True,exist_ok=True)
                if target.is_symlink():target.unlink()
                if not target.exists():target.symlink_to(source.resolve())
            external_count+=1
    (home/'external-data.json').write_text(json.dumps(dict(package=meta['package'],files=external_count,directory=str(external)),indent=2))
    (home/'preparation.json').write_text(json.dumps(dict(apk=str(apk),metadata=meta,obb=linked,engine=item['engine'],profileSource=item['profileSource'],profile=item['profile']),indent=2))
    env=dict(KL_VIEW='1',KL_MOLTENVR='1',KL_GLFB='0',KL_LIFECYCLE='1',KL_NET_OFFLINE='1',KL_ALARM='60',KL_FILES_DIR=str(userdata),KL_MVK_DIR=str(RUNTIME/'graphics/moltenvk'))
    shadercache=home/'pipeline-cache';shadercache.mkdir(exist_ok=True)
    env.update(KL_VK_FOZ_DIR=str(shadercache),KL_VK_FOZ_RECORD='auto',KL_VK_FOZ_REPLAY='auto',KL_VK_FOZ_REPLAY_BLOCK='1',KL_VK_FOZ_THREADS='6')
    if item['profile']=='game':env['KL_UNTESTED']='1'
    env['KL_APK']=str(apk)
    env['KL_MOLTENVR_VIDEO_DIR']=str(payload/'assets')
    env.update(defaults(item))
    executable,env,policy=configure_runtime(item,meta,payload,BASE,RUNTIME,env)
    (home/'runtime-selection.json').write_text(json.dumps(policy,indent=2))
    return dict(executable=str(executable),args=[item['profile'] if item.get('tree') else alias+'/lib/arm64-v8a'],cwd=str(session),env=env,log=str(home/'latest.log') if os.environ.get('APKVR_DEBUG')=='1' else os.devnull)
if __name__=='__main__':
    try:
        result=scan(sys.argv[2]) if sys.argv[1]=='scan' else prepare(sys.argv[2])
        print(json.dumps(result,ensure_ascii=False))
    except Exception as e:
        print(json.dumps({'error':str(e)},ensure_ascii=False));sys.exit(1)
