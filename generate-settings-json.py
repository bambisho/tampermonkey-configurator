#!/usr/bin/env python3
"""Generate a settings-only Tampermonkey provisioning JSON (no scripts).

Used by STEP 3 of tm-configure.ps1: applies TM settings via the managed
storage jsonImport policy WITHOUT touching the user-installed scripts.
Prints the structural hash to embed in tm-configure.ps1.
"""
import hashlib
import json

OUT = '/home/ubuntu/tm-easy/tm-settings.json'

data = {
    'version': '1',
    'settings': {
        'configMode': 100,               # Advanced config mode
        'external_update_interval': 'Always',
        'page_filter_mode': 'Disabled',
    },
}


def js_str(v):
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, float) and v == int(v):
        return str(int(v))
    return str(v)


def js_type(v):
    if v is None:
        return 'object'
    if isinstance(v, bool):
        return 'boolean'
    if isinstance(v, (int, float)):
        return 'number'
    if isinstance(v, str):
        return 'string'
    raise TypeError(str(type(v)))


def sha256_hex(s):
    return hashlib.sha256(s.encode('utf-8')).hexdigest()


def tm_hash(v):
    if isinstance(v, dict):
        return sha256_hex(''.join(tm_hash(v[k]) for k in sorted(v)))
    if isinstance(v, list):
        return sha256_hex(''.join(tm_hash(x) for x in v))
    return sha256_hex(f'{js_type(v)}:{js_str(v)}')


json.dump(data, open(OUT, 'w'), indent=2)
print(f'Written {OUT}')
print('Hash: 1:' + tm_hash(data))
