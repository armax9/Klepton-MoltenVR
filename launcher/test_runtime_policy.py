import unittest,tempfile,pathlib,json,hashlib
from runtime_policy import configure_runtime
class SharedRuntimePolicy(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.root=pathlib.Path(self.temp.name);self.base=self.root/'launcher';self.base.mkdir();self.runtime=self.root/'runtime';(self.runtime/'build').mkdir(parents=True);self.bin=self.runtime/'build/shared';self.bin.write_bytes(b'fixture release');self.payload=self.root/'payload';(self.payload/'lib/arm64-v8a').mkdir(parents=True)
  self.release={'id':'test','executable':'build/shared','sha256':hashlib.sha256(self.bin.read_bytes()).hexdigest(),'environment':{'KL_ALARM':'0','KL_MOLTENVR_NATIVE_CONE':'1'}};(self.base/'shared-runtime.json').write_text(json.dumps(self.release));self.profiles={};self.write_profiles()
 def tearDown(self):self.temp.cleanup()
 def write_profiles(self):(self.base/'profiles.json').write_text(json.dumps(self.profiles))
 def resolve(self,package='example.unknown',version='1',family='unity',env=None):
  return configure_runtime({'profile':'game','engineFamily':family,'engine':family,'obb':'Android/obb/'+package},{'package':package,'versionCode':version},self.payload,self.base,self.runtime,env or {})
 def test_all_engines_and_unknown_packages_share_binary(self):
  for family in ['unity','unreal','custom']:
   exe,env,info=self.resolve(family=family);self.assertEqual(exe,self.bin);self.assertEqual(env['KL_ALARM'],'0');self.assertEqual(env['KL_MOLTENVR_NATIVE_CONE'],'1');self.assertNotIn('KL_MVK_DETACH_DEAD_VIEWS',env)
 def test_stale_capture_not_inherited(self):
  _,env,_=self.resolve(env={'KL_VISUAL_TURN_PROBE':'1','KL_VK_OUT':'old','KL_VK_FRAME_EVENTS':'1','KL_TRACE':'1'});self.assertFalse(set(env)&{'KL_VISUAL_TURN_PROBE','KL_VK_OUT','KL_VK_FRAME_EVENTS','KL_TRACE'})
 def test_player_release_removes_diagnostic_flags(self):
  self.profiles={'example.unknown':{'runtimeEnv':{'KL_MOLTENVR_TIMING':'1','KL_GLFB_CONTENT_DIAG':'1','KL_VK_QUERY_TRACE':'1','KL_VK_VIDEO_IMPORT':'1'}}};self.write_profiles()
  _,env,_=self.resolve()
  self.assertEqual(env['KL_VK_VIDEO_IMPORT'],'1')
  self.assertFalse(set(env)&{'KL_MOLTENVR_TIMING','KL_GLFB_CONTENT_DIAG','KL_VK_QUERY_TRACE'})
 def test_alien_settings_require_exact_version_and_library(self):
  lib=self.payload/'lib/arm64-v8a/libUnreal.so';lib.write_bytes(b'known guest');self.profiles={'alien':{'versions':{'523063':{'guestLibrary':'libUnreal.so','guestSha256':hashlib.sha256(lib.read_bytes()).hexdigest(),'runtimeEnv':{'KL_VK_DEPTH_VARIANT':'1'}}}}};self.write_profiles();self.assertNotIn('KL_VK_DEPTH_VARIANT',self.resolve('alien','other')[1]);self.assertEqual(self.resolve('alien','523063')[1]['KL_VK_DEPTH_VARIANT'],'1');lib.write_bytes(b'changed');
  with self.assertRaises(RuntimeError):self.resolve('alien','523063')
 def test_companion_driver_is_explicit_and_fingerprinted(self):
  (self.base/'recipes').mkdir();driver=self.root/'special/libMoltenVK.dylib';driver.parent.mkdir();driver.write_bytes(b'known driver');recipe={'id':'memory-fix','driver_sha256':hashlib.sha256(driver.read_bytes()).hexdigest(),'required_env':{'KL_MVK_DETACH_DEAD_VIEWS':'1'}};(self.base/'recipes/driver.json').write_text(json.dumps(recipe));self.profiles={'syberia':{'driverRecipe':'driver.json','driverDirectory':'special'}};self.write_profiles();self.assertEqual(self.resolve('syberia')[1]['KL_MVK_DETACH_DEAD_VIEWS'],'1');self.assertNotIn('KL_MVK_DETACH_DEAD_VIEWS',self.resolve()[1]);driver.write_bytes(b'new');
  with self.assertRaises(RuntimeError):self.resolve('syberia')
 def test_modified_common_binary_rejected_for_every_game(self):
  self.bin.write_bytes(b'tampered');
  with self.assertRaises(RuntimeError):self.resolve()
 def test_shared_vulkan_driver_applies_to_unknown_engines(self):
  directory=self.runtime/'driver';directory.mkdir();lib=directory/'libMoltenVK.dylib';lib.write_bytes(b'known common driver')
  self.release['components']={'moltenvk':{'directory':'driver','files':{'libMoltenVK.dylib':hashlib.sha256(lib.read_bytes()).hexdigest()}}};(self.base/'shared-runtime.json').write_text(json.dumps(self.release))
  for family in ['unity','unreal','custom']:
   self.assertEqual(self.resolve('unknown.'+family,family=family)[1]['KL_MVK_DIR'],str(directory))
  lib.write_bytes(b'changed')
  with self.assertRaises(RuntimeError):self.resolve()
 def test_unity_openxr_capabilities_follow_plugin_not_package(self):
  plugin=self.payload/'lib/arm64-v8a/libUnityOpenXR.so';plugin.write_bytes(b'plugin')
  self.assertEqual(self.resolve('unknown.unity')[1]['KL_GL_MSRTT'],'1')
  self.assertNotIn('KL_GL_MSRTT',self.resolve('unknown.unreal',family='unreal')[1])
  plugin.unlink();self.assertNotIn('KL_GL_MSRTT',self.resolve()[1])
 def test_gles_component_is_checked_before_launch(self):
  directory=self.runtime/'angle';directory.mkdir();lib=directory/'libEGL.dylib';lib.write_bytes(b'known angle')
  self.release['components']={'angle':{'directory':'angle','files':{'libEGL.dylib':hashlib.sha256(lib.read_bytes()).hexdigest()}}};(self.base/'shared-runtime.json').write_text(json.dumps(self.release));self.profiles={'gles.game':{'graphics':'gles'}};self.write_profiles()
  self.assertEqual(self.resolve('gles.game')[1]['KL_GLFB'],'1')
  self.assertNotIn('KL_ANGLE_DIR',self.resolve('vulkan.game')[1])
  lib.write_bytes(b'changed')
  with self.assertRaises(RuntimeError):self.resolve('gles.game')
if __name__=='__main__':unittest.main()
