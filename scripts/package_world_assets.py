#!/usr/bin/env python3
"""Build the shared mobile World shell; verify pinned renderer packages via npm SRI."""
import argparse
import base64
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import ssl
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
PACKAGES = [
    ('maplibre-gl', '5.24.0', {'package/dist/maplibre-gl.js': 'maplibre-gl.js', 'package/dist/maplibre-gl.css': 'maplibre-gl.css'}),
    ('@mapbox/mapbox-gl-rtl-text', '0.3.0', {'package/dist/mapbox-gl-rtl-text.js': 'mapbox-gl-rtl-text.js'}),
]
CSP = "default-src 'none'; script-src 'self' blob: 'wasm-unsafe-eval'; worker-src 'self' blob:; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob: https://tiles.openfreemap.org; connect-src 'self' https://tiles.openfreemap.org https://photon.komoot.io https://valhalla1.openstreetmap.de; font-src 'self'; frame-src 'none'; object-src 'none'; base-uri 'self'"


def get(url):
    context = ssl.create_default_context(cafile=os.environ.get('SSL_CERT_FILE'))
    request = urllib.request.Request(url, headers={'User-Agent': 'IranNavigator-AndroidAssets/1.0'})
    with urllib.request.urlopen(request, timeout=120, context=context) as response:
        data = response.read(100 * 1024 * 1024 + 1)
        if len(data) > 100 * 1024 * 1024:
            raise ValueError('Package exceeds expected size')
        return data


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True)
    parser.add_argument('--platform', choices=['android', 'ios'], default='android')
    args = parser.parse_args()
    output = Path(args.output).resolve()
    if output == ROOT / 'web' or ROOT / 'web' in output.parents:
        raise ValueError('Refusing to overwrite shared web sources')
    output.mkdir(parents=True, exist_ok=True)
    cache = Path(os.environ.get('ANDROID_VENDOR_CACHE', '/tmp/iran-navigator-vendor'))
    cache.mkdir(parents=True, exist_ok=True)
    for name in ['index.html', 'app.css', 'app.mjs', 'compat.mjs', 'navigation.mjs', 'environment.mjs', 'roads.mjs', 'manifest.webmanifest']:
        shutil.copy2(ROOT / 'web' / name, output / name)
    shutil.copytree(ROOT / 'web/assets', output / 'assets', dirs_exist_ok=True)
    shutil.copy2(ROOT / 'shared/runtime/native-bridge.js', output / 'native-bridge.js')
    vendor = output / 'vendor'
    vendor.mkdir(exist_ok=True)
    notices = []
    for package, version, files in PACKAGES:
        metadata = json.loads(get(f'https://registry.npmjs.org/{package}/{version}'))
        integrity = metadata['dist']['integrity']
        algorithm, digest = integrity.split('-', 1)
        if algorithm != 'sha512':
            raise ValueError('Expected npm SHA-512 integrity')
        name = package.replace('/', '-').replace('@', '')
        archive = cache / f'{name}-{version}.tgz'
        payload = archive.read_bytes() if archive.exists() else get(metadata['dist']['tarball'])
        if base64.b64encode(hashlib.sha512(payload).digest()).decode() != digest:
            raise ValueError(f'Integrity mismatch for {package}@{version}')
        archive.write_bytes(payload)
        with tarfile.open(fileobj=io.BytesIO(payload), mode='r:gz') as tar:
            for source, target in files.items():
                member = tar.getmember(source)
                if not member.isfile() or member.size > 12 * 1024 * 1024:
                    raise ValueError('Unexpected renderer asset')
                (vendor / target).write_bytes(tar.extractfile(member).read())
            license_name = next(m.name for m in tar.getmembers() if m.name.lower() in ['package/license', 'package/license.txt', 'package/license.md'])
            (vendor / f'{name}-LICENSE.txt').write_bytes(tar.extractfile(license_name).read())
        notices.append({'package': package, 'version': version, 'integrity': integrity})
    (vendor / 'manifest.json').write_text(json.dumps(notices, indent=2) + '\n')
    index = (output / 'index.html').read_text()
    index = index.replace('https://unpkg.com/maplibre-gl@5.24.0/dist/maplibre-gl.js', './vendor/maplibre-gl.js')
    index = index.replace('https://unpkg.com/maplibre-gl@5.24.0/dist/maplibre-gl.css', './vendor/maplibre-gl.css')
    index = re.sub(r'<link\b[^>]*href="https://unpkg.com"[^>]*>', '', index)
    index = index.replace('<head>', '<head>\n<meta http-equiv="Content-Security-Policy" content="' + CSP + '">')
    marker = '<script type="module" src="./app.mjs"></script>'
    if marker not in index:
        raise ValueError('Shared application module tag changed; update packaging explicitly')
    index = index.replace(marker, '<script src="./native-bridge.js"></script>\n' + marker)
    (output / 'index.html').write_text(index)
    app = (output / 'app.mjs').read_text()
    url = 'https://unpkg.com/@mapbox/mapbox-gl-rtl-text@0.3.0/dist/mapbox-gl-rtl-text.js'
    if url not in app:
        raise ValueError('Shared RTL URL changed')
    app = app.replace(url, './vendor/mapbox-gl-rtl-text.js')
    registration = 'if ("serviceWorker" in navigator)'
    if registration not in app:
        raise ValueError('Shared service worker guard changed')
    app = app.replace(registration, 'if ("serviceWorker" in navigator && !window.NativeWorld)')
    (output / 'app.mjs').write_text(app)
    records = {}
    sources = [*ROOT.joinpath('web').glob('*.mjs'), ROOT / 'web/index.html', ROOT / 'web/app.css', ROOT / 'shared/runtime/native-bridge.js']
    for source in sources:
        destination = output / source.name
        if not destination.exists():
            raise ValueError(f'Shared source missing from bundle: {source.name}')
        records[str(source.relative_to(ROOT))] = {
            'source': hashlib.sha256(source.read_bytes()).hexdigest(),
            'bundled': hashlib.sha256(destination.read_bytes()).hexdigest(),
        }
    (output / 'world-manifest.json').write_text(json.dumps({'schema': 1, 'platform': args.platform, 'files': records}, indent=2) + '\n')
    print(f'Packaged {args.platform} World assets: {output}')
    print('Renderer versions and SHA-512 integrity verified; original licenses included.')


if __name__ == '__main__':
    main()
