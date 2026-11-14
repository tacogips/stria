#!/usr/bin/env python3
"""Archive/export Stria for TestFlight using local Xcode signing, as in Konjac."""
import argparse
import os
from pathlib import Path
import plistlib
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / '.build' / 'ios-release'
ARCHIVE = OUTPUT / 'StriaMobile.xcarchive'
EXPORT = OUTPUT / 'export'
XCODE = '/Applications/Xcode.app/Contents/Developer'


def run(command, stage):
    OUTPUT.mkdir(parents=True, exist_ok=True)
    # Do not pass vendor/API/Apple passwords into Xcode's build environment.
    env = {key: os.environ[key] for key in ('HOME', 'USER', 'TMPDIR') if key in os.environ}
    env.update(PATH='/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin', DEVELOPER_DIR=XCODE)
    log = OUTPUT / f'{stage}.log'
    with log.open('w') as stream:
        log.chmod(0o600)
        result = subprocess.run(command, cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT)
    print(f'{stage}: {"PASS" if result.returncode == 0 else "FAILED"}; local log: {log}')
    if result.returncode:
        # Only show diagnostics after removing private signing/account values.
        for line in log.read_text(errors='replace').splitlines():
            if 'error:' in line.lower() or '** archive failed **' in line.lower():
                import re
                line = re.sub(r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}', '[account]', line, flags=re.I)
                line = re.sub(r'\b[A-Z0-9]{10}\b', '[identifier]', line)
                for key, value in os.environ.items():
                    if value and len(value) > 5 and any(term in key for term in ('PASSWORD', 'SECRET', 'TOKEN', 'PRIVATE_KEY', 'TEAM_ID')):
                        line = line.replace(value, '[redacted]')
                print(line)
        raise SystemExit(result.returncode)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', choices=['archive', 'export', 'check'])
    args = parser.parse_args()
    if args.stage == 'archive':
        team = os.environ.get('APPLE_TEAM_ID')
        if not team:
            sys.exit('APPLE_TEAM_ID is required; inject it with kinko.')
        run(['xcodegen', 'generate', '--spec', 'Mobile/project.yml'], 'generate')
        command = [f'{XCODE}/usr/bin/xcodebuild', '-quiet', 'archive', '-project', 'Mobile/StriaMobile.xcodeproj',
                   '-scheme', 'StriaMobile', '-configuration', 'Release', '-destination', 'generic/platform=iOS',
                   '-archivePath', str(ARCHIVE), '-derivedDataPath', str(OUTPUT / 'DerivedData'),
                   '-clonedSourcePackagesDirPath', str(ROOT / 'Mobile/build/packages'),
                   '-disableAutomaticPackageResolution', '-skipPackageUpdates',
                   'CODE_SIGN_STYLE=Manual', 'CODE_SIGN_IDENTITY=Apple Distribution',
                   'PROVISIONING_PROFILE_SPECIFIER=Stria iOS App Store', f'DEVELOPMENT_TEAM={team}']
        run(command, 'archive')
    elif args.stage == 'export':
        if not ARCHIVE.exists():
            sys.exit('Archive first.')
        team = os.environ.get('APPLE_TEAM_ID')
        if not team:
            sys.exit('APPLE_TEAM_ID is required; inject it with kinko.')
        options = OUTPUT / 'ExportOptions.plist'
        options.write_bytes(plistlib.dumps({'method': 'app-store-connect', 'destination': 'export',
                                           'signingStyle': 'manual', 'teamID': team,
                                           'provisioningProfiles': {'me.tacogips.stria.mobile': 'Stria iOS App Store'},
                                           'signingCertificate': 'Apple Distribution',
                                           'manageAppVersionAndBuildNumber': False, 'uploadSymbols': True}))
        run([f'{XCODE}/usr/bin/xcodebuild', '-quiet', '-exportArchive', '-archivePath', str(ARCHIVE),
             '-exportPath', str(EXPORT), '-exportOptionsPlist', str(options)], 'export')
    else:
        import tempfile
        import zipfile
        ipas = list(EXPORT.glob('*.ipa'))
        if len(ipas) != 1:
            sys.exit('Expected one exported IPA.')
        with tempfile.TemporaryDirectory() as directory:
            with zipfile.ZipFile(ipas[0]) as archive:
                archive.extractall(directory)
            apps = list(Path(directory).glob('Payload/*.app'))
            if len(apps) != 1:
                sys.exit('Expected one app in IPA.')
            info = plistlib.loads((apps[0] / 'Info.plist').read_bytes())
            assert info['CFBundleIdentifier'] == 'me.tacogips.stria.mobile'
            assert set(info['UIDeviceFamily']) == {1, 2}
            assert (apps[0] / info['CFBundleExecutable']).stat().st_size > 0
            subprocess.run(['codesign', '--verify', '--deep', '--strict', str(apps[0])], check=True)
            signed = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(apps[0])],
                                    capture_output=True, check=True).stdout
            entitlements = plistlib.loads(signed)
            profile = plistlib.loads(subprocess.run(['security', 'cms', '-D', '-i',
                                                     str(apps[0] / 'embedded.mobileprovision')],
                                                    capture_output=True, check=True).stdout)
            for name in ('com.apple.developer.icloud-container-identifiers',
                         'com.apple.developer.ubiquity-container-identifiers'):
                assert 'iCloud.me.tacogips.stria' in entitlements.get(name, []), 'Missing signed iCloud container'
                assert 'iCloud.me.tacogips.stria' in profile['Entitlements'].get(name, []), 'Profile lacks iCloud container'
            assert 'CloudDocuments' in entitlements.get('com.apple.developer.icloud-services', [])
            services = profile['Entitlements'].get('com.apple.developer.icloud-services', [])
            assert 'CloudDocuments' in services or '*' in services, 'Profile lacks iCloud document service'
            print(f"IPA verified: {info['CFBundleIdentifier']} {info['CFBundleShortVersionString']} ({info['CFBundleVersion']}), iPhone + iPad")


if __name__ == '__main__':
    main()
