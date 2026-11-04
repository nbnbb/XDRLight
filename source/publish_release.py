#!/usr/bin/env python3
"""Build, sign and prepare an HTTPS update release; private keys stay in Keychain."""
import argparse, json, subprocess
from pathlib import Path
from urllib.parse import urlparse
parser = argparse.ArgumentParser()
parser.add_argument('--base-url', required=True, help='Public HTTPS directory, e.g. https://example.com/xdrlight/')
parser.add_argument('--output', required=True, help='Directory holding existing and new release archives')
args = parser.parse_args()
url = urlparse(args.base_url)
if url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment:
    parser.error('A public HTTPS directory without credentials, query or fragment is required')
base = Path(__file__).resolve().parent.parent
config_path = base / 'source/release.json'
config = json.loads(config_path.read_text())
output = Path(args.output).resolve(); output.mkdir(parents=True, exist_ok=True)
archive = output / f'XDRLight-{config["version"]}.zip'
if archive.exists():
    raise SystemExit('This version archive already exists. Increase version/build; never replace a released build.')
appcast_tool = base / 'source/vendor/bin/generate_appcast'
if not appcast_tool.is_file():
    raise SystemExit('Missing Sparkle generate_appcast tool in source/vendor/bin')
config['feed_url'] = args.base_url.rstrip('/') + '/appcast.xml'
config_path.write_text(json.dumps(config, indent=2) + '\n')
subprocess.run([str(base / 'source/build.sh')], check=True)
subprocess.run(['ditto', '--norsrc', '--noextattr', '--noqtn', '-c', '-k', '--keepParent', str(base/'XDRLight.app'), str(archive)], check=True)
notes = output / f'XDRLight-{config["version"]}.html'
if not notes.exists(): notes.write_text('<h2>XDRLight '+config['version']+'</h2><p>亮度增强、实时热状态和签名在线更新。</p>')
subprocess.run([str(base/'source/vendor/bin/generate_appcast'), '--account', 'local.xdrlight', '--maximum-deltas', '0', '--download-url-prefix', args.base_url.rstrip('/')+'/', '--embed-release-notes', str(output)], check=True)
print('Upload release files first, then appcast.xml last. Feed:', config['feed_url'])
