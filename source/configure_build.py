#!/usr/bin/env python3
import json, plistlib, re
from pathlib import Path
from urllib.parse import urlparse
base = Path(__file__).resolve().parent.parent
config = json.loads((base / 'source/release.json').read_text())
assert re.fullmatch(r'\d+\.\d+\.\d+', config['version']), 'Version must be X.Y.Z'
assert isinstance(config['build'], int) and config['build'] > 0
feed = config.get('feed_url', '')
if feed:
    url = urlparse(feed)
    assert url.scheme == 'https' and url.hostname and not url.username and not url.password and not url.fragment, 'HTTPS feed required'
path = base / 'XDRLight.app/Contents/Info.plist'
info = plistlib.loads(path.read_bytes())
info['CFBundleShortVersionString'] = config['version']
info['CFBundleVersion'] = str(config['build'])
if feed: info['SUFeedURL'] = feed
else: info.pop('SUFeedURL', None)
path.write_bytes(plistlib.dumps(info))
