#!/usr/bin/env python3
"""Package a staged player folder without Finder metadata or developer files."""
import argparse,hashlib,pathlib,shutil,subprocess,tempfile,zipfile
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('staged_folder',type=pathlib.Path)
p.add_argument('output',type=pathlib.Path)
a=p.parse_args();a.output=a.output.resolve();a.output.parent.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='apkvr-package-') as tmp:
 folder=pathlib.Path(tmp)/'APK VR Library'
 shutil.copytree(a.staged_folder,folder,copy_function=shutil.copyfile,ignore=shutil.ignore_patterns('__pycache__','.DS_Store','._*','*.pyc'))
 for name in ['runtime/bin/runtime','Install.command','APK VR Library.app/Contents/MacOS/APKLibrary']:(folder/name).chmod(0o755)
 subprocess.run(['codesign','--force','-s','-',str(folder/'APK VR Library.app')],check=True)
 subprocess.run(['codesign','--verify','--deep','--strict',str(folder/'APK VR Library.app')],check=True)
 subprocess.run(['/opt/homebrew/bin/python3',str(folder/'verify_release.py')],check=True)
 with zipfile.ZipFile(a.output,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
  for f in sorted(folder.rglob('*')):
   if f.is_file():z.write(f,str(f.relative_to(folder.parent)))
print(a.output)
print('SHA256:',hashlib.sha256(a.output.read_bytes()).hexdigest())
