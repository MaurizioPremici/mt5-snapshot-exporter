# MT5 Snapshot Exporter — implemented behavior

Release: **1.2.0**. The MQL program displays version **1.02**. JSON schema: **1.0**.

A manual export creates H4, H1, M15 and M5 native PNG charts and one snapshot.json file under Desktop/MT5Data. Each export has a separate folder. The supported installation is MT5 on macOS through Wine with a local Python delivery helper.

## Counts and preferences

Each timeframe has separate screenshot and closed-JSON counts. Defaults are 100 image candles for every timeframe and 300/500/500/600 closed candles for H4/H1/M15/M5. Image counts accept 20–500; JSON counts must cover the image and cannot exceed 10,000. Valid edits are saved automatically. The panel supports dragging, collapse, hide and reopen.

Image counts include the forming candle. JSON closed-candle counts exclude it; its OHLC is stored separately with is_closed=false. Closed candles run from oldest to newest.

## Native images

Temporary clean charts show the symbol, timeframe, price scale, time axis, captured Bid/Ask and timestamps. The right margin defaults to 12.5%, configurable between 10% and 15%. Width is calibrated to the requested candle count using native zoom; images are not reconstructed or resized.

A dashed Frozen Bid line and numeric tag mark the captured Bid. A Forming arrow identifies the unfinished candle. Each chart records its own capture quote and time. Labels are native MT5 objects; price-tag alignment uses the plot border measured in the calibration PNG.

The image verifier counts full and partial candles separately. The default allowed difference from the requested full count is five bars. Any mismatch is disclosed; a larger mismatch fails the export. JSON counts must match exactly.

## Data and consistency

Prices are JSON numbers formatted to the symbol's decimal precision. Quotes come from one SymbolInfoTick call per observation. The export includes symbol specifications, bar OHLC, server timestamps, tick volume and raw bar spread. Exact-symbol positions and pending orders are read separately; no account identifiers or balance are exported.

A common reference precedes sequential captures. The exporter repeats the whole group if a forming-bar identity or the serialized position/order state changes before the final check. There are at most three attempts by default. Captures are not atomic; forming OHLC may differ between the data read and image capture.

The helper checks the schema, chronological order, OHLC, counts, PNG dimensions and checksums. Files are copied to a temporary destination and the complete folder is then renamed. A failed package is marked failed with its errors.

## Limits

Broker UTC offset and device clock accuracy are not independently verified. Tick age remains unavailable, with an explanation. Successful exports normally report complete_with_warnings. Positions and pending orders have explicit read statuses; an empty array does not establish absence after a failed read.

No orders are placed, changed or cancelled. User indicators and drawings are not copied. A default template containing an Expert Advisor or script is rejected before temporary charts are opened. Exports stay local.

The original Italian planning document is preserved in [docs/SPEC-original-it.md](docs/SPEC-original-it.md). It includes proposals and earlier defaults; this document, the README and the code describe this release. Executed checks are in [VALIDATION.md](VALIDATION.md).
