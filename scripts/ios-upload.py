#!/usr/bin/env python3
"""Upload the verified Stria IPA to TestFlight with project Kinko credentials."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
IPAS = list((ROOT / '.build/ios-release/export').glob('*.ipa'))
if len(IPAS) != 1:
    sys.exit('Expected exactly one exported IPA.')
subprocess.run([sys.executable, str(ROOT / 'scripts/ios-release.py'), 'check'], cwd=ROOT, check=True)
for name in ('APP_STORE_CONNECT_API_KEY_ID', 'APP_STORE_CONNECT_API_PRIVATE_KEY', 'APPLE_ID', 'APPLE_PASSWORD'):
    if not os.environ.get(name):
        sys.exit(f'{name} is required; inject it with project Kinko.')
if os.environ.get('APP_STORE_CONNECT_API_KEY_TYPE') != 'individual':
    sys.exit('This uploader expects the individual App Store Connect API key.')

key = os.environ['APP_STORE_CONNECT_API_PRIVATE_KEY'].replace('\\n', '\n')
with tempfile.NamedTemporaryFile('w', suffix='.json', delete=False, encoding='utf-8') as stream:
    json.dump({'key_id': os.environ['APP_STORE_CONNECT_API_KEY_ID'], 'issuer_id': None,
               'key': key, 'duration': 1200, 'in_house': False}, stream)
    key_file = Path(stream.name)
key_file.chmod(0o600)

environment = {name: os.environ[name] for name in ('HOME', 'USER', 'TMPDIR') if name in os.environ}
environment.update(PATH='/Users/taco/.local/share/mise/shims:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin',
                   DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer',
                   FASTLANE_OPT_OUT_USAGE='1', FASTLANE_SKIP_UPDATE_CHECK='1',
                   FASTLANE_USER=os.environ['APPLE_ID'], FASTLANE_PASSWORD=os.environ['APPLE_PASSWORD'],
                   FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD=os.environ['APPLE_PASSWORD'])
command = ['fastlane', 'pilot', 'upload', '--api_key_path', str(key_file), '--ipa', str(IPAS[0]),
           '--app_identifier', 'me.tacogips.stria.mobile', '--skip_waiting_for_build_processing', 'false',
           '--skip_submission', 'true', '--wait_processing_interval', '30',
           '--wait_processing_timeout_duration', '1200']
log = ROOT / '.build/ios-release/upload.log'
try:
    with log.open('w') as stream:
        log.chmod(0o600)
        result = subprocess.run(command, cwd=ROOT, env=environment, stdout=stream, stderr=subprocess.STDOUT)
finally:
    key_file.unlink(missing_ok=True)
print(f'Upload and processing: {"PASS" if result.returncode == 0 else "FAILED"}; private local log: {log}')
if result.returncode:
    sys.exit(result.returncode)
subprocess.run([sys.executable, str(ROOT / 'scripts/ios-testflight.py')], cwd=ROOT, check=True)
