import unittest
from engine_profiles import detect,defaults,ARM64
class EngineRouting(unittest.TestCase):
 def test_unknown_unity(self):
  d=detect({ARM64+'libmain.so',ARM64+'libunity.so'});self.assertEqual((d['engineFamily'],d['profileSource'],d['supported']),('unity','engine',True))
 def test_unknown_unreal_generations(self):
  for lib in ['libUE4','libUnreal']:
   d=detect({ARM64+lib+'.so'});self.assertEqual(d['entry'],lib);self.assertTrue(d['supported']);d['obb']='Android/obb/example';self.assertEqual(defaults(d)['KL_GUEST_OBB'],d['obb']);self.assertNotIn('KL_MVK_DETACH_DEAD_VIEWS',defaults(d))
 def test_game_recipe_wins_over_ambiguous_libraries(self):
  names={ARM64+x+'.so' for x in ['libmain','libunity','libUnreal']}
  self.assertFalse(detect(names)['supported']);d=detect(names,{'entry':'libUnreal'});self.assertEqual(d['profileSource'],'game');self.assertEqual(d['entry'],'libUnreal')
 def test_incomplete_or_32bit_is_not_launchable(self):
  for names in [{ARM64+'libunity.so'},{'lib/armeabi-v7a/libUnreal.so'},{ARM64+'libgodot_android.so'}]:self.assertFalse(detect(names)['supported'])
 def test_stale_package_recipe_does_not_override_engine(self):
  d=detect({ARM64+'libUnreal.so'},{'entry':'libmain'});self.assertEqual(d['engineFamily'],'unreal')
class ApkInspection(unittest.TestCase):
 def test_unknown_apk_gets_unreal_route_and_remains_unverified(self):
  import tempfile,zipfile,pathlib
  from library import inspect
  with tempfile.TemporaryDirectory() as folder:
   p=pathlib.Path(folder)/'Example.apk'
   with zipfile.ZipFile(p,'w') as z:
    z.writestr('AndroidManifest.xml','<manifest package="example.unknown" xmlns:android="http://schemas.android.com/apk/res/android" android:versionCode="1"><application/></manifest>')
    z.writestr(ARM64+'libUnreal.so',b'fixture')
   d=inspect(p,p.parent)
   self.assertIsNotNone(d);self.assertTrue(d['supported']);self.assertFalse(d['verified']);self.assertEqual(d['profile'],'game');self.assertIsNone(d['tree']);self.assertEqual(d['obb'],'Android/obb/example.unknown')
if __name__=='__main__':unittest.main()
