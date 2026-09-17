# Validation record

Date: 2026-09-17.

Executed on the installed MT5 terminal under Wine:
- Two accepted four-chart exports delivered four PNGs and snapshot.json to Desktop/MT5Data.
- Final package: EURUSD_1789636866_304807610. H4/H1/M15/M5 image counts: 100/100/100/100. Closed JSON counts: 300/500/500/600.
- The final H4 request was 99; actual native count was 100. The difference is explicitly recorded within the configured five-bar tolerance. Counts are not reported as exact matches when they differ.
- Read-back schema, OHLC, chronological order, actual image dimensions, candle counts and copied image hashes passed.
- Visually reviewed native price/time axes and the corrected, complete Bid/Ask and timestamp header.
- Collapse, expand, hide, reopen and title-bar dragging were exercised. Saved panel position and a custom H4 value of 99 were restored on relaunch.
- Refreshed Navigator after installing the panel control indicator; removed stale control instances during startup.
- Main script and controls compiled with zero errors and zero warnings. Eight focused Python integrity tests passed.

The original export failures came from empty native program-name handling, a clipped candle at MT5's three-pixel border, and the native Doji colour missing from the image counter. The captured images remain native MT5 output.

Limits:
- Acceptance status is complete_with_warnings: broker UTC offset and absolute device-clock accuracy are not verified. These are explicit JSON warnings, not claims of live freshness.
- No controlled live bar-rollover or position/order-change test was run. No trading operation was performed by the exporter or testing code.
- This record is a software export check, not trading-strategy or statistical validation.

## Exporter 1.2 update — 2026-09-17

- Right margin set to 12.5%, configurable from 10% to 15%. Native width is calibrated while preserving requested candle counts.
- Added a frozen Bid line, right-edge numeric price tag and a forming-candle arrow. The price tag uses the measured native PNG plot border for vertical alignment.
- Accepted export EURUSD_1789639104_307045392: image counts 150/150/100/100; closed JSON counts 300/500/500/600. Four PNGs and JSON delivered. Final package schema, prices, OHLC and image counts checked again.
- Verified over 7,600 numeric price fields with at most the symbol's five decimal places. No price fields were converted into strings.
- Direct terminal observation showed equal Bid/Ask (1.14776/1.14776) and later a one-point difference (1.14769/1.14770). The H4 export independently recorded Bid 1.14727, Ask 1.14728, spread 0.00001. Zero spread is therefore not forced by serialization. This is an observation at capture time, not a statement about current quotes or total trading costs.
- Main compilation: zero errors and warnings. Eight focused integrity tests passed. After visual review, the Frozen Bid caption was raised slightly to separate it from the numeric tag on narrower images.
- The existing broker-time and clock warnings remain. No trading operations were performed.
