#!/usr/bin/env python3
"""Compile with the installed MetaEditor; leave terminal/account untouched."""
import os, pathlib, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parents[1]
PREFIX = pathlib.Path.home() / 'Library/Application Support/net.metaquotes.wine.metatrader5'
MT = PREFIX / 'drive_c/Program Files/MetaTrader 5'
WINE = '/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine64'
source = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv)>1 else ROOT/'src/MT5SnapshotExporter.mq5'
log = source.with_suffix('.log')
if log.exists(): log.unlink()
env = dict(os.environ, WINEPREFIX=str(PREFIX), WINEDEBUG='-all')
args = [WINE, str(MT/'MetaEditor64.exe'), '/compile:Z:'+str(source).replace('/','\\'), '/log']
try:
    proc = subprocess.run(args, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
except subprocess.TimeoutExpired:
    print('MetaEditor timeout'); sys.exit(2)
if log.exists():
    data = log.read_bytes()
    text = data.decode('utf-16') if data.startswith((b'\xff\xfe',b'\xfe\xff')) else data.decode('utf-8',errors='replace')
    print(text)
    sys.exit(0 if '0 errors, 0 warnings' in text else 1)
print(proc.stdout.decode(errors='replace')[-2000:]); print('Compilation log not found'); sys.exit(2)
