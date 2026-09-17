"""Purposeful synthetic fault checks. No connection to an MT5 account."""
import importlib.util
import tempfile
import unittest
from pathlib import Path
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location("bridge",ROOT/"bridge/bridge.py")
bridge=importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)

class IntegrityTests(unittest.TestCase):
    def test_full_and_partial_native_colour_groups(self):
        # Synthetic drawing: tests counting only, not MT5 rendering compatibility.
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/"sample.png"
            image=Image.new("RGB",(800,600),(15,23,32));draw=ImageDraw.Draw(image)
            for x in (0,16,32,48):
                draw.line((x,180,x,320),fill=(45,212,191))
                draw.rectangle((x-5,220,x+5,280),fill=(45,212,191))
            image.save(path)
            counts=bridge.inspect_png(path)
            self.assertEqual(counts["full_bars"],3)
            self.assertEqual(counts["partial_bars"],1)
            self.assertEqual(counts["width"],800)

    def test_native_three_pixel_border(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/"sample.png"
            image=Image.new("RGB",(800,600),(15,23,32));draw=ImageDraw.Draw(image)
            for x in (2,18,34,50):
                draw.rectangle((max(3,x-5),220,x+5,280),fill=(45,212,191))
            image.save(path)
            result=bridge.inspect_png(path)
            self.assertEqual((result["full_bars"],result["partial_bars"]),(3,1))

    def test_clipped_candles_are_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/"sample.png"
            image=Image.new("RGB",(800,600),(15,23,32))
            ImageDraw.Draw(image).rectangle((30,50,40,300),fill=(248,113,113))
            image.save(path)
            with self.assertRaisesRegex(ValueError,"clipped"):
                bridge.inspect_png(path)

    def test_active_default_template_is_rejected_before_chart_open(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);folder=root/"MQL5/Profiles/Templates";folder.mkdir(parents=True)
            self.assertEqual(bridge.template_preflight(root),"OK")
            (folder/"default.tpl").write_text("<chart>\n<expert>\nname=ExampleEA\n</expert>\n</chart>")
            with self.assertRaisesRegex(ValueError,"refused"):
                bridge.template_preflight(root)

if __name__=="__main__": unittest.main()

class PackageFaultTests(unittest.TestCase):
    def make_package(self, folder):
        import copy, json
        from datetime import datetime, timedelta
        schema=json.loads((ROOT/"snapshot.schema.json").read_text())
        def sample(s):
            if "const" in s: return s["const"]
            if "enum" in s: return s["enum"][0]
            if "anyOf" in s: return sample(s["anyOf"][0])
            t=s.get("type")
            if t=="object": return {k:sample(v) for k,v in s["properties"].items()}
            if t=="array": return []
            if t=="integer": return s.get("minimum",0)
            if t=="number": return s.get("minimum",1)
            if t=="boolean": return True
            if t=="string":
                pattern=s.get("pattern","")
                if "\\d{4}" in pattern: return "2026-01-05T00:00:00"+("Z" if pattern.endswith("Z$") else "")
                if "[0-9]" in pattern: return "123"
                return "synthetic"
            return None
        data=sample(schema);data["status"]="complete_with_warnings";data["attempt_count"]=1
        data["symbol_spec"]["symbol"]="SYNTHETIC"
        data["reference_quote"]["spread_price"]=0
        data["reference_quote"]["spread_points"]=0
        data["charts"]=[]
        chart_schema=schema["properties"]["charts"]["items"]
        for tf in bridge.TF:
            c=sample(chart_schema)
            c.update(timeframe=tf,requested_screenshot_bars=20,actual_screenshot_bars=20,
                     partial_screenshot_bars=0,screenshot_tolerance_bars=0,
                     requested_closed_bars=20,exported_closed_bars=20,
                     screenshot_file=tf+".png",screenshot_width=800,screenshot_height=600,
                     status="complete",capture_quote=copy.deepcopy(data["reference_quote"]))
            bars=[]
            for i in range(21):
                b=sample(chart_schema["properties"]["forming_candle"])
                b["time_open_server"]=(datetime(2026,1,5)+timedelta(hours=i)).isoformat()
                b["is_closed"]=i<20;bars.append(b)
            c["closed_candles"]=bars[:-1];c["forming_candle"]=bars[-1]
            c["visible_first_open_server"]=bars[1]["time_open_server"]
            c["visible_last_open_server"]=bars[-1]["time_open_server"]
            c["history_first_open_server"]=bars[0]["time_open_server"]
            c["history_last_closed_open_server"]=bars[-2]["time_open_server"]
            image=Image.new("RGB",(800,600),(15,23,32));draw=ImageDraw.Draw(image)
            for x in range(24,24+20*16,16):
                draw.line((x,180,x,320),fill=(45,212,191))
                draw.rectangle((x-5,220,x+5,280),fill=(45,212,191))
            image.save(folder/(tf+".png"));data["charts"].append(c)
        return data

    def test_exact_counts_pass_and_short_json_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            folder=Path(d);data=self.make_package(folder)
            bridge.validate_package(data,folder)
            data["charts"][0]["closed_candles"].pop()
            with self.assertRaisesRegex(ValueError,"history count"):
                bridge.validate_package(data,folder)

    def test_invalid_ohlc_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            folder=Path(d);data=self.make_package(folder)
            data["charts"][1]["closed_candles"][3]["low"]=2
            with self.assertRaisesRegex(ValueError,"invalid OHLC"):
                bridge.validate_package(data,folder)

    def test_missing_image_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            folder=Path(d);data=self.make_package(folder);(folder/"M5.png").unlink()
            with self.assertRaises(FileNotFoundError):
                bridge.validate_package(data,folder)

    def test_failure_report_still_obeys_schema(self):
        with tempfile.TemporaryDirectory() as d:
            report=bridge.failure_report({"export_id":"synthetic"},ValueError("simulated invalid data"))
            bridge.validate_package(report,Path(d))
            self.assertEqual(report["positions_status"],"error")
            self.assertEqual(report["status"],"failed")
