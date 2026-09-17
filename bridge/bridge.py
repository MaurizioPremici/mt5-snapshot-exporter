#!/usr/bin/env python3
"""Local file bridge. No terminal control, network calls or trading operations."""
from __future__ import annotations
import argparse, hashlib, json, os, re, shutil, time, traceback
from pathlib import Path
from datetime import datetime, timezone
from PIL import Image
import jsonschema
import numpy as np

COLORS = {(45, 212, 191), (248, 113, 113)}
TF = ['H4', 'H1', 'M15', 'M5']
ROOT = Path(__file__).resolve().parents[1]


def atomic_text(path, text):
    tmp = path.with_name(path.name + '.writing')
    tmp.write_text(text, encoding='utf-8')
    os.replace(tmp, path)


def inspect_png(path):
    with Image.open(path) as im:
        if im.format != 'PNG':
            raise ValueError('Not a PNG')
        im.load()
        rgb = im.convert('RGB')
        width, height = rgb.size
        # Candle colours are reserved exclusively for bodies and wicks.
        pixels = np.asarray(rgb)
        mask = np.zeros(pixels.shape[:2], dtype=bool)
        for colour in COLORS:
            mask |= np.all(pixels == colour, axis=2)
        ys, cols = np.nonzero(mask)
        ymin, ymax = (int(ys.min()), int(ys.max())) if len(ys) else (height,0)
        xs = np.flatnonzero(mask.any(axis=0)).tolist()
        groups = []
        for x in xs:
            if not groups or x > groups[-1][-1] + 1:
                groups.append([x])
            else:
                groups[-1].append(x)
        typical_width = int(np.median([len(g) for g in groups])) if groups else 0
        # MT5 clips candles inside its 3-pixel plot border, not at image x=0.
        partial = [g for g in groups if g[0] <= 1 or g[-1] >= width-2
                   or (g is groups[0] and g[0] <= 3 and len(g) < typical_width)]
        full = [g for g in groups if g not in partial]
        if not full or ymin < 140 or ymax >= height-30:
            raise ValueError('Candles missing, covered by header, or vertically clipped')
        centers = [(g[0] + g[-1])/2 for g in full]
        distances = [b-a for a,b in zip(centers,centers[1:])]
        if distances and max(distances)-min(distances) > 2:
            raise ValueError('Unexpected candle spacing; pixel count cannot be trusted')
        # Native bottom plot border locates the price projection in the PNG.
        border=np.all(pixels == (188,199,214),axis=2).sum(axis=1)
        candidates=np.flatnonzero(border > width*.7)
        candidates=candidates[(candidates > height-100)&(candidates < height-5)]
        plot_bottom=int(candidates[-1]) if len(candidates) else -1
        return {'width':width, 'height':height, 'plot_bottom_y':plot_bottom, 'full_bars':len(full),
                'partial_bars':len(partial), 'first_center_x':centers[0],
                'last_center_x':centers[-1], 'candle_top_y':ymin,
                'candle_bottom_y':ymax, 'count_method':'reserved_native_candle_colours',
                'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}


def warning(code, scope, message, affects):
    return dict(code=code, scope=scope, message=message, affects=affects)


def validate_package(data, stage):
    schema = json.loads((ROOT/'snapshot.schema.json').read_text())
    jsonschema.Draft202012Validator(schema).validate(data)
    if data['status'] == 'failed':
        return
    if [c['timeframe'] for c in data['charts']] != TF:
        raise ValueError('Wrong chart order')
    if data['operational_state_check']['result'] not in ('unchanged', 'unverifiable'):
        raise ValueError('Operational state changed')
    for chart in data['charts']:
        name = chart['timeframe']
        if chart['screenshot_file'] != name+'.png':
            raise ValueError('Unexpected image path')
        stats = inspect_png(stage/(name+'.png'))
        bars = chart['closed_candles']
        if len(bars) != chart['requested_closed_bars'] or len(bars) != chart['exported_closed_bars']:
            raise ValueError(name+': history count mismatch')
        if stats['full_bars'] != chart['actual_screenshot_bars']:
            raise ValueError(name+': image count changed after calibration')
        if abs(stats['full_bars']-chart['requested_screenshot_bars']) > chart['screenshot_tolerance_bars']:
            raise ValueError(name+': visual count outside tolerance')
        if stats['partial_bars'] != chart['partial_screenshot_bars']:
            raise ValueError(name+': partial bar count changed')
        if [stats['width'],stats['height']] != [chart['screenshot_width'],chart['screenshot_height']]:
            raise ValueError(name+': PNG dimension mismatch')
        times = [b['time_open_server'] for b in bars]
        if times != sorted(set(times)):
            raise ValueError(name+': duplicate or unordered bars')
        if any(not b['is_closed'] for b in bars) or chart['forming_candle']['is_closed']:
            raise ValueError(name+': wrong closed/forming classification')
        if times[-1] >= chart['forming_candle']['time_open_server']:
            raise ValueError(name+': forming bar is not newer')
        for b in bars+[chart['forming_candle']]:
            if not 0 < b['low'] <= min(b['open'],b['close']) <= max(b['open'],b['close']) <= b['high']:
                raise ValueError(name+': invalid OHLC')
        n=stats['full_bars']-1
        if n < 1 or n > len(bars):
            raise ValueError(name+': visual interval exceeds JSON')
        if chart['visible_first_open_server'] != bars[-n]['time_open_server'] or chart['visible_last_open_server'] != chart['forming_candle']['time_open_server']:
            raise ValueError(name+': visual time interval mismatch')
        chart['image_verification'] = stats
    for quote in [data['reference_quote']]+[c['capture_quote'] for c in data['charts']]:
        if not 0 < quote['bid'] <= quote['ask']:
            raise ValueError('Invalid Bid/Ask')
        point=data['symbol_spec']['point']
        if abs(quote['spread_price']-(quote['ask']-quote['bid'])) > point*1e-6:
            raise ValueError('Spread mismatch')
    for item in data['positions']+data['pending_orders']:
        if item['symbol'] != data['symbol_spec']['symbol']:
            raise ValueError('Foreign symbol in operational data')
    jsonschema.Draft202012Validator(schema).validate(data)


def template_preflight(mt):
    # ChartOpen can load default.tpl. Refuse potentially active defaults.
    for directory in (mt/'MQL5/Profiles/Templates',mt/'Profiles/Templates'):
        if not directory.exists():
            continue
        for file in directory.iterdir():
            if file.name.casefold() == 'default.tpl':
                raw=file.read_bytes()
                content=raw.decode('utf-16') if raw.startswith((b'\xff\xfe',b'\xfe\xff')) else raw.decode('utf-8',errors='replace')
                if '<expert>' in content.casefold() or '<script>' in content.casefold():
                    raise ValueError('default.tpl contains an Expert Advisor or script; clean chart creation refused')
    return 'OK'


def failure_report(data, error):
    now=datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    identity=str(data.get('export_id','unknown'))
    return {
        'schema_version':'1.0','exporter_version':str(data.get('exporter_version','unknown')),
        'export_id':identity,'attempt_id':identity+'-rejected','attempt_count':0,
        'symbol_spec':{'symbol':str(data.get('symbol_spec',{}).get('symbol','unknown'))},
        'broker_time':{'time_basis':'broker_server','timezone_name':None,
          'utc_offset_seconds_at_reference':None,'source':'Rejected package','status':'unavailable'},
        'capture_clock':{'utc_source':'Python device clock; validation report only',
          'verification_status':'unverified','duration_source':'unavailable',
          'server_timestamp_format':'YYYY-MM-DDTHH:mm:ss, broker server','utc_resolution_seconds':1},
        'connection_status':{'connected_at_reference':False,'connected_at_completion':False},
        'reference_time_utc':None,'reference_time_server':None,
        'export_started_at_utc':now,'export_completed_at_utc':now,
        'snapshot_window_ms':0,'data_collection_duration_ms':0,'reference_quote':None,
        'positions_status':'error','positions_observation':{'started_at_utc':'','completed_at_utc':''},
        'positions':[],'pending_orders_status':'error',
        'pending_orders_observation':{'started_at_utc':'','completed_at_utc':''},'pending_orders':[],
        'operational_state_check':{'result':'not_verified','completed_at_utc':'',
          'comparison':'Package rejected before acceptance','limit':'No operational state established'},
        'status':'failed','quality_warnings':[],
        'errors':[warning('PACKAGE_VALIDATION_FAILED','package',str(error)[:600],'package_integrity')],
        'charts':[]
    }


def process(root, dest, mt):
    for request in root.glob('*.preflight'):
        ack=request.with_suffix('.allow')
        if ack.exists(): continue
        try: answer=template_preflight(mt)
        except Exception as e: answer='ERROR '+str(e)
        atomic_text(ack,answer)
    for stage in root.iterdir():
        if not stage.is_dir() or stage.is_symlink() or not re.fullmatch(r'[a-zA-Z0-9_-]+', stage.name): continue
        for request in stage.glob('*.inspect'):
            ack=request.with_suffix('.count')
            if ack.exists(): continue
            try:
                stats=inspect_png(request.with_suffix('.png'))
                answer=f"OK {stats['full_bars']} {stats['partial_bars']} {stats['width']} {stats['height']} {stats['plot_bottom_y']}"
            except Exception as e: answer='ERROR '+str(e)
            atomic_text(ack,answer)
        ready=stage/'ready'
        ack=stage/'delivered.txt'
        if not ready.exists() or ack.exists(): continue
        try:
            data=json.loads((stage/'snapshot.pending.json').read_text(encoding='utf-8-sig'), parse_constant=lambda v: (_ for _ in ()).throw(ValueError(v)))
            try:
                validate_package(data,stage)
            except Exception as e:
                data=failure_report(data,e)
                validate_package(data,stage)
            symbol=re.sub(r'[^A-Za-z0-9_.-]','_',data.get('symbol_spec',{}).get('symbol','unknown'))[:40]
            name=f"{symbol}_{stage.name}"
            final=dest/name
            partial=dest/('.partial_'+name)
            if final.exists():
                old=json.loads((final/'snapshot.json').read_text())
                if old.get('export_id') != data['export_id']:
                    raise ValueError('Destination collision')
                atomic_text(ack,('ERROR ' if old['status']=='failed' else 'OK ')+str(final))
                continue
            partial.mkdir(mode=0o700,exist_ok=True)
            for tf in TF:
                png=stage/(tf+'.png')
                if png.is_file() and not png.is_symlink(): shutil.copy2(png,partial/png.name)
            data['count_verification'] = [
                {'timeframe': c['timeframe'],
                 'screenshot_requested': c['requested_screenshot_bars'],
                 'screenshot_saved': c['image_verification']['full_bars'],
                 'json_closed_requested': c['requested_closed_bars'],
                 'json_closed_saved': len(c['closed_candles']),
                 'forming_saved_separately': c['forming_candle'] is not None,
                 'verified': True}
                for c in data.get('charts',[]) if 'image_verification' in c
            ]
            for c in data.get('charts',[]):
                if data['status']!='failed' and hashlib.sha256((partial/c['screenshot_file']).read_bytes()).hexdigest()!=c['image_verification']['sha256']:
                    raise ValueError('Copied PNG checksum mismatch')
            data['delivery']={'destination':'Desktop/MT5Data','delivered_at_utc':datetime.now(timezone.utc).isoformat(), 'validation':'passed' if data['status']!='failed' else 'failed'}
            atomic_text(partial/'snapshot.json',json.dumps(data,ensure_ascii=False,allow_nan=False,indent=2)+'\n')
            os.rename(partial,final)
            # Keep rejected source material in staging for diagnosis.
            cleanup_errors=[]
            if data['status']!='failed':
                for f in stage.iterdir():
                    if f.name!='delivered.txt' and f.is_file():
                        try: f.unlink()
                        except OSError as e: cleanup_errors.append(str(e))
            if cleanup_errors:
                data['status']='complete_with_warnings'
                data['quality_warnings'].append(warning('STAGING_CLEANUP_FAILED','delivery',
                    '; '.join(cleanup_errors)[:600],'temporary_file_cleanup'))
                atomic_text(final/'snapshot.json',json.dumps(data,ensure_ascii=False,allow_nan=False,indent=2)+'\n')
            atomic_text(ack,('ERROR ' if data['status']=='failed' else 'OK ')+str(final))
        except Exception as e:
            atomic_text(ack,'ERROR '+str(e)[:400])


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--terminal',type=Path,required=True)
    p.add_argument('--destination',type=Path,required=True)
    p.add_argument('--once',action='store_true')
    a=p.parse_args()
    root=a.terminal/'MQL5/Files/MTSE'
    root.mkdir(parents=True,exist_ok=True)
    a.destination.mkdir(parents=True,exist_ok=True,mode=0o700)
    while True:
        try: process(root,a.destination,a.terminal)
        except Exception: traceback.print_exc()
        if a.once: break
        time.sleep(.2)

if __name__=='__main__': main()
