"""One runtime release for every APK; measured exceptions are profile data."""
import hashlib,json,pathlib

def _check(path,expected,label):
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest()!=expected:
        raise RuntimeError(label+' does not match the validated release. Restore the matching file.')

def configure_runtime(item,meta,payload,base,runtime_root,env):
    release=json.loads((base/'shared-runtime.json').read_text())
    executable=runtime_root/release['executable']
    _check(executable,release['sha256'],'Shared runtime')
    profiles=json.loads((base/'profiles.json').read_text())
    spec=profiles.get(meta['package'],{})
    env=dict(env);env.update(release['environment'])
    # One fingerprinted Vulkan driver for every engine. A measured companion
    # driver below may override it when its extra lifetime ABI is required.
    graphics=release.get('components',{}).get('moltenvk')
    if graphics and spec.get('graphics')!='gles':
        directory=runtime_root/graphics['directory']
        for filename,fingerprint in graphics['files'].items():
            _check(directory/filename,fingerprint,'Shared Vulkan driver '+filename)
        env['KL_MVK_DIR']=str(directory)
    # Unknown games get the same engine adapter and shared fixes as known ones.
    if item['engineFamily']=='unreal':
        env['KL_GUEST_OBB']=item['obb']
        env['KL_VK_VIN_FILL']='1'
    if item['profile']=='game':env['KL_UNTESTED']='1'
    # Unity OpenXR's single-pass MSAA target must use the supported implicit
    # resolve extensions together. Otherwise it allocates unsupported GLES
    # multisample-array textures and every eye framebuffer is incomplete.
    if item['engineFamily']=='unity' and (payload/'lib/arm64-v8a/libUnityOpenXR.so').is_file():
        env['KL_GL_MSRTT']='1'
    if spec.get('graphics')=='gles':
        component=release['components']['angle']
        directory=runtime_root/component['directory']
        for filename,fingerprint in component['files'].items():
            _check(directory/filename,fingerprint,'ANGLE '+filename)
        # This native compositor samples ordinary UVs; it does not unwarp
        # ANGLE's rasterization-rate-map physical layout (visionOS does).
        env.update(KL_GLFB='1',KL_GLFB_MTL='1',KL_VRR='0',KL_ANGLE_DIR=str(directory))
    env.update(spec.get('runtimeEnv',{}))
    exceptions=[]
    if spec.get('driverRecipe'):
        recipe=json.loads((base/'recipes'/spec['driverRecipe']).read_text())
        driver=runtime_root.parent/spec['driverDirectory']/'libMoltenVK.dylib'
        _check(driver,recipe['driver_sha256'],'Companion graphics driver')
        env['KL_MVK_DIR']=str(driver.parent);env.update(recipe.get('required_env',{}))
        exceptions.append(recipe['id'])
    version=spec.get('versions',{}).get(str(meta['versionCode']))
    if version:
        if version.get('guestLibrary'):
            _check(payload/'lib'/'arm64-v8a'/version['guestLibrary'],version['guestSha256'],'Version-specific guest library')
        env.update(version.get('runtimeEnv',{}));exceptions.append(meta['package']+':'+str(meta['versionCode']))
    # Capture is an explicit diagnostic run, never inherited from a previous game.
    for key in list(env):
        if key.startswith(('KL_VISUAL_','KL_VK_OUT','KL_GLFB_TRACE','KL_GLFB_DUMP')) or any(tag in key for tag in ('_TRACE','_DIAG','_PROBE','_CAPTURE','_TIMING')) or key in ('KL_SAMPLE_MS','KL_MOLTENVR_CAPTURE_AT','KL_VK_MOD_DUMP','KL_VK_SUBPASS_DUMP','KL_VK_FRAME_EVENTS','KL_VK_PASS_BIND_TRACE','KL_TRACE'):
            env.pop(key)
    policy={'release':release['id'],'runtime':str(executable),'sha256':release['sha256'],
            'engine':item['engine'],'package':meta['package'],'exceptions':exceptions}
    return executable,env,policy
