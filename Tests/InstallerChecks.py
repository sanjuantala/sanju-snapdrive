#!/usr/bin/env python3
"""Run the real installer with isolated files and mocked Mac release tools."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
import zipfile

PROJECT = Path(__file__).resolve().parents[1]
APP = "Sanju's SnapDrive.app"
ASSET = 'Sanju-SnapDrive-1.5.0-macOS.zip'
TOOLS = r'''
import json, os, pathlib, shutil, stat, subprocess, sys, zipfile
root = pathlib.Path(os.environ['INSTALL_FIXTURE_ROOT'])
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with (root/'tools.log').open('a') as log: log.write(json.dumps([name]+args)+'\n')
def count(key):
    f=root/(key+'.count'); value=int(f.read_text())+1 if f.exists() else 1; f.write_text(str(value)); return value
if name=='uname':
    print(os.environ.get('FIXTURE_OS','Darwin') if args==['-s'] else os.environ.get('FIXTURE_ARCH','arm64'))
elif name=='sw_vers': print(os.environ.get('FIXTURE_VERSION','13.0'))
elif name=='pgrep':
    n=count('pgrep')
    sys.exit(0 if os.environ.get('FIXTURE_RUNNING')=='1' or (os.environ.get('FIXTURE_RUNNING_LATE')=='1' and n>1) else 1)
elif name=='curl':
    if os.environ.get('FIXTURE_DOWNLOAD_FAIL')=='1': sys.exit(22)
    url=next(a for a in args if a.startswith('https://'))
    target=pathlib.Path(args[args.index('--output')+1])
    source=(pathlib.Path(os.environ['INSTALL_FIXTURE_PROJECT'])/'install.sh') if url.endswith('/install.sh') else root/'assets'/url.rsplit('/',1)[-1]
    shutil.copyfile(source,target)
elif name=='codesign':
    n=count('codesign'); sys.exit(1 if str(n)==os.environ.get('FIXTURE_SIGNATURE_FAIL') else 0)
elif name=='file':
    print('Mach-O 64-bit executable ppc' if os.environ.get('FIXTURE_ARCH_FAIL')=='1'
          else 'Mach-O universal binary with 2 architectures: [x86_64:Mach-O 64-bit executable x86_64] [arm64:Mach-O 64-bit executable arm64]')
elif name=='ditto':
    if args[:2]==['-x','-k']:
        if os.environ.get('FIXTURE_EXTRACT_FAIL')=='1': sys.exit(1)
        destination=pathlib.Path(args[3])
        with zipfile.ZipFile(args[2]) as archive:
            for info in archive.infolist():
                output=destination/info.filename
                if info.is_dir(): output.mkdir(parents=True,exist_ok=True); continue
                output.parent.mkdir(parents=True,exist_ok=True)
                mode=info.external_attr >> 16
                if stat.S_ISLNK(mode): output.symlink_to(archive.read(info).decode()); continue
                output.write_bytes(archive.read(info)); output.chmod(mode & 0o777 or 0o644)
    else:
        if os.environ.get('FIXTURE_COPY_FAIL')=='1': sys.exit(1)
        shutil.copytree(args[0],args[1],symlinks=True)
elif name=='mv':
    if os.environ.get('FIXTURE_MOVE_FAIL')=='1' and '/.snapdrive-install.' in args[0] and args[0].endswith("Sanju's SnapDrive.app"):
        sys.exit(1)
    sys.exit(subprocess.call(['/bin/mv']+args))
'''


class InstallerChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='snapdrive-installer-tests-')
        self.root = Path(self.temporary.name).resolve()
        self.tools = self.root/'tools'
        self.tools.mkdir()
        (self.root/'assets').mkdir()
        self.destination = self.root/'Applications with spaces'
        self.target = self.destination/APP
        for tool in ['uname','sw_vers','pgrep','curl','codesign','file','ditto','mv']:
            p=self.tools/tool
            p.write_text('#!'+sys.executable+'\n'+TOOLS)
            p.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.tools)+':/usr/bin:/bin:/usr/sbin:/sbin', INSTALL_FIXTURE_ROOT=str(self.root), INSTALL_FIXTURE_PROJECT=str(PROJECT))
        self.make_release()

    def tearDown(self):
        self.temporary.cleanup()

    def make_app(self, folder, bundle='com.snapdrive.screenshot', version='1.5.0', marker='new'):
        (folder/'Contents/MacOS').mkdir(parents=True)
        (folder/'Contents/Helpers').mkdir()
        (folder/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':bundle,'CFBundleShortVersionString':version}))
        for path in ['Contents/MacOS/SnapDrive','Contents/Helpers/SnapDriveBrowserHost']:
            p=folder/path; p.write_text('#!/bin/sh\nexit 0\n'); p.chmod(0o755)
        (folder/'marker').write_text(marker)

    def make_release(self, bundle='com.snapdrive.screenshot', version='1.5.0', extra=None, missing=None, symlink=False):
        source=self.root/'release-source'
        if source.exists(): shutil.rmtree(source)
        self.make_app(source/APP,bundle,version)
        if missing: (source/APP/missing).unlink()
        if symlink: (source/APP/'outside').symlink_to('/tmp')
        asset=self.root/'assets'/ASSET
        with zipfile.ZipFile(asset,'w') as archive:
            for p in (source/APP).rglob('*'):
                if p.is_symlink():
                    info=zipfile.ZipInfo(str(p.relative_to(source))); info.create_system=3; info.external_attr=(stat.S_IFLNK|0o777)<<16; archive.writestr(info,os.readlink(p))
                elif p.is_file(): archive.write(p,str(p.relative_to(source)))
            if extra: archive.writestr(extra,'unexpected')
        digest=hashlib.sha256(asset.read_bytes()).hexdigest()
        (self.root/'assets/SHA256SUMS').write_text(digest+'  '+ASSET+'\n')

    def existing(self, bundle='com.snapdrive.screenshot'):
        self.make_app(self.target,bundle=bundle,version='1.4.0',marker='old')

    def run_install(self, overrides=None, wrapper=False, extra=()):
        env=dict(self.env,**(overrides or {}))
        script=PROJECT/('Install.command' if wrapper else 'install.sh')
        result=subprocess.run(['/bin/bash',str(script),'--no-open','--destination',str(self.destination),*extra],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        return result

    def calls(self,name):
        log=self.root/'tools.log'
        return [json.loads(l) for l in log.read_text().splitlines() if json.loads(l)[0]==name] if log.exists() else []

    def assert_clean(self):
        self.assertFalse((self.destination/'.snapdrive-install.lock').exists())
        self.assertEqual(list(self.destination.glob('.snapdrive-install.*')),[])

    def test_fresh_install_and_native_arch(self):
        result=self.run_install()
        self.assertEqual(result.returncode,0,result.stdout)
        self.assertEqual((self.target/'marker').read_text(),'new')
        self.assertEqual(len(self.calls('codesign')),3)
        self.assertEqual([Path(c[-1]).name for c in self.calls('file')], ['SnapDrive','SnapDriveBrowserHost'])
        self.assertEqual(len(self.calls('curl')),2)
        self.assertTrue(all('--proto' in c and '=https' in c for c in self.calls('curl')))
        self.assert_clean()

    def test_intel_arch(self):
        result=self.run_install({'FIXTURE_ARCH':'x86_64'})
        self.assertEqual(result.returncode,0,result.stdout)
        self.assertEqual(len(self.calls('file')), 2)

    def test_checksum_mismatch_preserves_existing_app(self):
        self.existing()
        (self.root/'assets/SHA256SUMS').write_text('0'*64+'  '+ASSET+'\n')
        result=self.run_install()
        self.assertNotEqual(result.returncode,0)
        self.assertIn('checksum check',result.stdout)
        self.assertEqual((self.target/'marker').read_text(),'old')
        self.assertEqual(self.calls('ditto'),[])

    def test_missing_or_duplicate_checksum(self):
        sums=self.root/'assets/SHA256SUMS'; original=sums.read_text()
        for value in ['',original+original]:
            with self.subTest(value=value):
                sums.write_text(value); result=self.run_install()
                self.assertNotEqual(result.returncode,0)
                self.assertFalse(self.target.exists())

    def test_extraction_failure_preserves_existing_app(self):
        self.existing(); result=self.run_install({'FIXTURE_EXTRACT_FAIL':'1'})
        self.assertNotEqual(result.returncode,0)
        self.assertEqual((self.target/'marker').read_text(),'old')
        self.assert_clean()

    def test_network_failure_preserves_existing_app(self):
        self.existing(); result=self.run_install({'FIXTURE_DOWNLOAD_FAIL':'1'})
        self.assertNotEqual(result.returncode,0)
        self.assertEqual((self.target/'marker').read_text(),'old')
        self.assert_clean()

    def test_update_retains_previous_app(self):
        self.existing(); result=self.run_install()
        self.assertEqual(result.returncode,0,result.stdout)
        backups=list(self.destination.glob('.snapdrive-backup.*'))
        self.assertEqual(len(backups),1)
        self.assertEqual((backups[0]/APP/'marker').read_text(),'old')
        self.assertEqual((self.target/'marker').read_text(),'new')
        self.assertIn('kept for rollback',result.stdout)
        self.assert_clean()

    def test_move_failure_restores_previous_app(self):
        self.existing(); result=self.run_install({'FIXTURE_MOVE_FAIL':'1'})
        self.assertNotEqual(result.returncode,0)
        self.assertEqual((self.target/'marker').read_text(),'old')
        self.assertIn('previous app was restored',result.stdout)
        self.assert_clean()

    def test_final_signature_failure_restores_previous_app(self):
        self.existing(); result=self.run_install({'FIXTURE_SIGNATURE_FAIL':'3'})
        self.assertNotEqual(result.returncode,0)
        self.assertEqual((self.target/'marker').read_text(),'old')
        self.assertIn('previous app was restored',result.stdout)
        self.assert_clean()

    def test_final_signature_failure_removes_new_install(self):
        result=self.run_install({'FIXTURE_SIGNATURE_FAIL':'3'})
        self.assertNotEqual(result.returncode,0)
        self.assertFalse(self.target.exists())
        self.assert_clean()

    def test_source_or_stage_signature_failure_leaves_existing_app(self):
        self.existing()
        for call in ['1','2']:
            with self.subTest(call=call):
                (self.root/'codesign.count').unlink(missing_ok=True)
                result=self.run_install({'FIXTURE_SIGNATURE_FAIL':call})
                self.assertNotEqual(result.returncode,0)
                self.assertEqual((self.target/'marker').read_text(),'old')
                self.assert_clean()

    def test_running_app_blocks_before_download(self):
        result=self.run_install({'FIXTURE_RUNNING':'1'})
        self.assertNotEqual(result.returncode,0)
        self.assertIn('Quit',result.stdout)
        self.assertEqual(self.calls('curl'),[])

    def test_app_started_during_download_blocks_replacement(self):
        self.existing(); result=self.run_install({'FIXTURE_RUNNING_LATE':'1'})
        self.assertNotEqual(result.returncode,0)
        self.assertEqual((self.target/'marker').read_text(),'old')
        self.assert_clean()

    def test_unsupported_platforms(self):
        for value in [{'FIXTURE_OS':'Linux'},{'FIXTURE_VERSION':'12.7.6'},{'FIXTURE_VERSION':'unknown'},{'FIXTURE_ARCH':'riscv'}]:
            with self.subTest(value=value):
                result=self.run_install(value)
                self.assertNotEqual(result.returncode,0)
                self.assertEqual(self.calls('curl'),[])

    def test_symlink_destination_left_untouched(self):
        actual=self.root/'real-folder'; actual.mkdir(); self.destination.symlink_to(actual)
        result=self.run_install()
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(list(actual.iterdir()),[])
        self.assertTrue(self.destination.is_symlink())

    def test_symlink_app_left_untouched(self):
        actual=self.root/'other.app'; self.make_app(actual)
        self.destination.mkdir(); self.target.symlink_to(actual)
        result=self.run_install()
        self.assertNotEqual(result.returncode,0)
        self.assertTrue(self.target.is_symlink())
        self.assertTrue(actual.exists())

    def test_unrelated_app_left_untouched(self):
        self.existing(bundle='another.app'); result=self.run_install()
        self.assertNotEqual(result.returncode,0)
        self.assertEqual((self.target/'marker').read_text(),'old')
        self.assertEqual(self.calls('curl'),[])

    def test_bad_archive_paths_rejected_before_extraction(self):
        for extra in ['../outside.txt','/tmp/outside.txt',APP+'/../outside.txt','unexpected.txt']:
            with self.subTest(extra=extra):
                self.make_release(extra=extra); result=self.run_install()
                self.assertNotEqual(result.returncode,0)
                self.assertEqual(self.calls('ditto'),[])
                self.assertFalse(self.target.exists())

    def test_release_identity_version_completeness_and_links(self):
        for values in [{'bundle':'another.app'},{'version':'9.0'},{'missing':'Contents/MacOS/SnapDrive'},{'missing':'Contents/Helpers/SnapDriveBrowserHost'},{'symlink':True}]:
            with self.subTest(values=values):
                self.make_release(**values); result=self.run_install()
                self.assertNotEqual(result.returncode,0)
                self.assertFalse(self.target.exists())

    def test_existing_lock_left_untouched(self):
        self.existing(); lock=self.destination/'.snapdrive-install.lock'; lock.mkdir()
        result=self.run_install()
        self.assertNotEqual(result.returncode,0)
        self.assertTrue(lock.is_dir())
        self.assertEqual((self.target/'marker').read_text(),'old')

    def test_missing_arch_preserves_existing_app(self):
        self.existing(); result=self.run_install({'FIXTURE_ARCH_FAIL':'1'})
        self.assertNotEqual(result.returncode,0)
        self.assertEqual((self.target/'marker').read_text(),'old')

    def test_bundled_double_click_wrapper(self):
        result=self.run_install(wrapper=True)
        self.assertEqual(result.returncode,0,result.stdout)
        self.assertTrue(self.target.exists())

    def test_downloaded_double_click_wrapper_uses_pinned_official_script(self):
        standalone=self.root/'Install.command'; shutil.copyfile(PROJECT/'Install.command',standalone)
        result=subprocess.run(['/bin/bash',str(standalone),'--no-open','--destination',str(self.destination)],env=self.env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        self.assertEqual(result.returncode,0,result.stdout)
        script_url='https://raw.githubusercontent.com/sanjuantala/sanju-snapdrive/v1.5.0/install.sh'
        self.assertTrue(any(script_url in call for call in self.calls('curl')))

    def test_help_is_read_only(self):
        result=subprocess.run(['/bin/bash',str(PROJECT/'install.sh'),'--help'],env=self.env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        self.assertEqual(result.returncode,0,result.stdout)
        self.assertEqual(self.calls('curl'),[])
        self.assertFalse(self.destination.exists())

    def test_no_em_dash_or_security_bypass(self):
        for name in ['install.sh','Install.command']:
            text=(PROJECT/name).read_text()
            self.assertNotIn(chr(0x2014),text)
            self.assertNotIn('xattr',text)
            self.assertNotIn('spctl --master-disable',text)
            self.assertNotIn('killall',text)
            self.assertNotIn('sudo',text)


if __name__=='__main__':
    unittest.main(verbosity=2)
