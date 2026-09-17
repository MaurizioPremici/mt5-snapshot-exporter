#!/usr/bin/env python3
"""Install the read-only MT5 script and the local Desktop delivery helper."""
import os, plistlib, shutil, subprocess, sys, time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
MT=Path.home()/'Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5'
APP=Path.home()/'Library/Application Support/MT5SnapshotExporter'
DEST=Path.home()/'Desktop/MT5Data'
LABEL='local.mt5.snapshot-exporter'
LAUNCH=Path.home()/'Library/LaunchAgents'/f'{LABEL}.plist'
if not (ROOT/'src/MT5SnapshotExporter.ex5').is_file(): raise SystemExit('Compile first.')
(APP/'bridge').mkdir(parents=True,exist_ok=True,mode=0o700)
DEST.mkdir(parents=True,exist_ok=True,mode=0o700)
for f in ('bridge/bridge.py','snapshot.schema.json'):
    shutil.copy2(ROOT/f,APP/f)
scripts=MT/'MQL5/Scripts/MT5SnapshotExporter'
scripts.mkdir(exist_ok=True)
for name in ('MT5SnapshotExporter.ex5','MT5SnapshotExporter.mq5','SnapshotData.mqh'):
    shutil.copy2(ROOT/'src'/name,scripts/name)
indicators=MT/'MQL5/Indicators/MT5SnapshotExporter'
indicators.mkdir(exist_ok=True)
for name in ('SnapshotPanelControls.ex5','SnapshotPanelControls.mq5'):
    shutil.copy2(ROOT/'src'/name,indicators/name)
LAUNCH.parent.mkdir(exist_ok=True)
plist=dict(Label=LABEL,ProgramArguments=[sys.executable,str(APP/'bridge/bridge.py'),'--terminal',str(MT),'--destination',str(DEST)],RunAtLoad=True,KeepAlive=True,ThrottleInterval=10,StandardOutPath=str(APP/'helper.log'),StandardErrorPath=str(APP/'helper.log'),ProcessType='Background')
LAUNCH.write_bytes(plistlib.dumps(plist))
subprocess.run(['launchctl','bootout',f'gui/{os.getuid()}/{LABEL}'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
for attempt in range(5):
    result=subprocess.run(['launchctl','bootstrap',f'gui/{os.getuid()}',str(LAUNCH)],capture_output=True)
    if result.returncode==0: break
    time.sleep(0.5)
else:
    raise RuntimeError(result.stderr.decode())
print('Installed MT5SnapshotExporter under Navigator > Scripts.')
print('Destination:',DEST)
print('Local helper:',APP)
