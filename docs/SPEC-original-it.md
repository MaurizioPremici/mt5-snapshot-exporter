# MT5 Snapshot Exporter — Functional specification

Versione della specifica: **0.3 — revisione per utilità analitica**.
Deriva dalla versione 0.2 fornita dall’utente e la sostituisce come proposta documentale. Non attesta implementazione, compatibilità Wine o prove già eseguite. Schema JSON di destinazione: `1.0`, ancora da implementare.

## 1. Obiettivo e limiti

Esportatore per MetaTrader 5 desktop, inizialmente su macOS tramite Wine, con interfaccia in inglese. Una richiesta manuale produce quattro screenshot PNG nativi, nell’ordine H4 → H1 → M15 → M5, e un JSON del simbolo selezionato.

Gli screenshot servono alla lettura della struttura; il JSON permette di verificare prezzi, candele e stato operativo senza interpolazioni visuali. La quantità di dati non garantisce completezza dell’analisi, redditività o validità di un ingresso.

Sono consentite esclusivamente letture di mercato, posizioni e ordini pendenti del simbolo esatto. Nessun inserimento, modifica o cancellazione di ordini; nessuna chiusura di posizioni; nessuna modifica a SL, TP o volume. Nessuna esportazione di credenziali, identificativi del conto, saldo o strumenti diversi. Nessun invio automatico esterno.

Non sono richiesti nella prima versione calcolo di segnali, riconoscimento automatico dei pattern, calendario macro, storico dei tick, backtest o dimensionamento delle posizioni. La disponibilità dei dati non modifica il metodo di analisi del progetto.

## 2. Quantità e copertura

| Timeframe | Target candele nello screenshot | Candele chiuse nel JSON |
|---|---:|---:|
| H4 | 150 | 300 |
| H1 | 150 | 500 |
| M15 | 120 | 500 |
| M5 | 120 | 600 |

I conteggi sono configurabili separatamente per timeframe e salvati nelle preferenze. Il JSON predefinito contiene esattamente 1.900 candele chiuse, più fino a quattro candele correnti separate.

Il target visivo comprende la candela corrente, quando presente: 149 chiuse più una corrente per H4/H1; 119 più una per M15/M5. Si contano le candele integralmente visibili; quelle tagliate ai bordi sono registrate separatamente e non entrano nel conteggio.

**Revisione del vincolo visivo:** cercare prima il numero esatto; ammettere una tolleranza configurabile, inizialmente ±5 candele, solo per gli screenshot nativi. Ogni scostamento produce un avviso e riporta richiesto/effettivo. Uno scostamento oltre la tolleranza fallisce il requisito visivo. La tolleranza è una scelta di prodotto, non un limite documentato di MT5.

I conteggi JSON restano esatti: storico insufficiente significa esportazione non completa. Non generare barre per raggiungere il conteggio. Esportare gli estremi temporali reali; non promettere settimane o giorni fissi. Lo storico può essere esteso manualmente per cercare strutture precedenti.

## 3. Candele e provenienza dei prezzi

Per ogni candela esportare:

- `time_open_server`: ora di apertura nel riferimento del server, con formato dichiarato e senza suffisso UTC inventato.
- `open`, `high`, `low`, `close`: valori numerici originali MT5.
- `is_closed`: stato esplicito.
- `tick_volume`: valore originale, se disponibile; non rappresenta il volume globale del mercato Forex.
- `spread_points_raw`: campo spread della barra fornito dalla sorgente, in point; dato accessorio, non spread medio/massimo né ricostruzione dello spread all’istante dello SL.

Il volume reale è opzionale. Se esportato, indicare disponibilità e provenienza; non equipararlo al tick volume e non interpretare automaticamente uno zero come volume reale verificato.

Per timeframe:

- `closed_candles`: ordinate dalla più vecchia alla più recente, tutte chiuse rispetto al riferimento del tentativo accettato.
- `forming_candle`: barra corrente separata, `is_closed: false`, oppure `null` con motivo. Il Close è provvisorio.
- Timestamp strettamente crescenti, senza duplicati. Ogni OHLC deve essere finito e soddisfare `low <= min(open, close) <= max(open, close) <= high`.
- Nessuna interpolazione, riempimento dei vuoti o ricostruzione da immagini.
- Uno stato senza nuovi tick non dimostra che la barra corrente sia chiusa.

`symbol_spec.chart_price_basis` deve riportare `bid`, `last` oppure `unknown`, dalla proprietà effettiva del simbolo. Non assumere il tipo di prezzo dal nome della coppia. MT5 espone questa distinzione tramite `SYMBOL_CHART_MODE`. [Documentazione Symbol Properties](https://www.mql5.com/en/docs/constants/environment_state/marketinfoconstants).

OHLC e quotazioni Bid/Ask sono fonti distinte. Non ricostruire barre Ask sommando lo spread corrente alle barre Bid. Dai soli OHLC non si conosce l’ordine intrabar con cui massimo e minimo sono stati raggiunti.

I dati accessori della barra derivano dalla struttura nativa; il loro significato non deve essere ampliato oltre quello documentato. [Documentazione MqlRates](https://www.mql5.com/en/docs/constants/structures/mqlrates).

## 4. Riferimento temporale e coerenza dell’intero gruppo

Ogni tentativo ha un `reference_time_utc`, un riferimento server quando verificabile e un `attempt_id`. La preparazione dello storico e dei grafici precede il riferimento.

1. Leggere gli orari delle barre correnti di tutti i timeframe.
2. Fissare il riferimento, acquisire dati e stato operativo con gli intervalli effettivi di lettura.
3. Congelare i dati acquisiti in memoria.
4. Acquisire in sequenza i quattro PNG e gli eventuali indicatori con i propri timestamp.
5. Ricontrollare le barre correnti e lo stato operativo dopo l’ultima immagine.

Se cambia una barra in uno dei quattro timeframe, ripetere **l’intero gruppo**, comprese quotazioni, posizioni, pendenti e indicatori. Non unire immagini nuove con JSON o posizioni del tentativo precedente. Massimo predefinito: tre tentativi; poi `failed` con motivazione.

Registrare `snapshot_window_ms`, `data_collection_duration_ms`, numero di tentativi e intervalli di acquisizione. Una durata eccessiva genera un avviso rispetto a una soglia configurabile; proposta iniziale 10 secondi per la finestra di acquisizione dopo la preparazione. È una soglia diagnostica da verificare sul dispositivo, non una garanzia di validità finanziaria.

La raccolta non è atomica. Anche senza cambio barra, High/Low/Close correnti, quotazioni e indicatori possono mutare. Il riferimento è un ancoraggio temporale comune: non significa che ogni valore corrente sia stato osservato esattamente in quell’istante.

Le candele chiuse visibili devono appartenere al relativo `closed_candles`. La barra corrente deve avere la stessa identità temporale del JSON, ma i suoi valori possono differire per il diverso momento di acquisizione. Esplicitare `forming_values_may_differ: true` e non usare lo screenshot come prova di identità esatta del tick.

## 5. Quotazioni, orologi e specifiche

`reference_quote` e ciascuna `capture_quote` contengono Bid/Ask della stessa lettura `MqlTick`, timestamp originale del tick, riferimento temporale dichiarato e intervallo della lettura. Non effettuare due letture indipendenti per assemblare Bid e Ask. [Documentazione SymbolInfoTick](https://www.mql5.com/en/docs/marketinformation/symbolinfotick).

Esportare spread derivato in prezzo e point; non richiedere il pip per simboli senza convenzione verificata. Quotazioni non valide o Ask minore di Bid generano un errore esplicito. Lo zero non deve sostituire un prezzo mancante.

Il riquadro dello screenshot mostra la `capture_quote` congelata ed è etichettato `Captured quote`, con ora del tick e ora della lettura. Eventuali linee native che continuano ad aggiornarsi non sono presentate come la stessa misura: nasconderle nella modalità pulita oppure documentare questa distinzione.

Registrare stato di connessione e, quando calcolabile su basi temporali compatibili, età del tick. Se non calcolabile, `null` con motivo. Un tick vecchio non è nuovo perché la lettura è appena avvenuta; non attribuire automaticamente l’assenza di tick a mercato chiuso o disconnessione.

`broker_time` contiene:

- `time_basis: "broker_server"`;
- `timezone_name`, se verificato, altrimenti `null`;
- `utc_offset_seconds_at_reference`, se verificato, altrimenti `null`;
- `source` e `status: verified | unavailable`.

Non ricavare il fuso del broker da quello del Mac o da un tick vecchio. Non applicare l’offset corrente a date storiche senza verificarne la validità. I timestamp server originali restano disponibili anche quando è possibile aggiungere una conversione UTC.

Documentare anche la fonte degli orari UTC del dispositivo e il loro stato di verifica. `TimeGMT` dipende dall’ambiente temporale locale: l’uso della funzione non dimostra da solo la sincronizzazione dell’orologio. Le durate di processo devono usare un contatore monotono; niente precisione temporale inventata. [Documentazione TimeGMT](https://www.mql5.com/en/docs/dateandtime/timegmt).

Fuso del broker sconosciuto: `complete_with_warnings`, con limite sulle conversioni temporali, senza scartare OHLC validi dello stesso server.

`symbol_spec` contiene nome completo, `digits`, `point`, `tick_size`, `contract_size`, `chart_price_basis`, `is_custom` e, se disponibili, `stops_level_points` e `freeze_level_points`. Gli ultimi due documentano vincoli del broker, non la qualità tecnica di uno SL. Non confondere point, tick e pip; non assumere equivalenze fra lotti e unità. [Documentazione delle proprietà del simbolo](https://www.mql5.com/en/docs/constants/environment_state/marketinfoconstants).

## 6. Posizioni aperte e ordini pendenti

Esportare tutte le posizioni del simbolo esatto, una sola volta nel JSON, senza aggregare posizioni opposte.

Per posizione: `position_id`, `position_ticket`, `symbol`, `direction: buy | sell`, `open_price`, `volume`, `volume_unit: lots`, `sl`, `tp`, `opened_at_server`, `updated_at_server` quando disponibile e intervallo di osservazione UTC.

Identificativo e ticket sono stringhe distinte: mappare esplicitamente `POSITION_IDENTIFIER` e `POSITION_TICKET`. SL/TP non impostati sono `null`; una lettura fallita deve avere uno stato differente dall’assenza verificata. [Documentazione Position Properties](https://www.mql5.com/en/docs/constants/tradingconstants/positionproperties).

`positions_status: success | partial | error`; `positions: []` significa nessuna posizione solo con `success`.

**Aggiunta per distinguere gli stati operativi:** esportare anche `pending_orders`, separati dalle posizioni, per il simbolo esatto. Campi minimi: identificativo come stringa, tipo esatto dell’ordine, prezzo richiesto, eventuale prezzo stop-limit, volume residuo e unità, SL/TP, scadenza e timestamp se disponibili. `pending_orders_status` distingue successo, parziale ed errore. L’ordine pendente non è un ingresso eseguito.

Rileggere lo stato operativo alla fine: confrontare presenza, direzione, prezzo di apertura, volume, SL/TP delle posizioni e proprietà dei pendenti. Se cambiano, ripetere l’intero gruppo entro il limite dei tentativi. Non fare ripartire l’esportazione per la sola variazione del prezzo corrente o del profitto flottante. Uguaglianza iniziale/finale significa assenza di variazioni rilevate, non prova assoluta di immobilità durante l’intervallo.

Profitto monetario e valuta del conto non sono obbligatori per questa versione. In loro assenza non promettere calcoli monetari netti o dimensionamento del rischio.

## 7. Modalità grafica e indicatori

Scelta iniziale: **grafici puliti a candele standard**, senza indicatori o disegni aggiunti automaticamente. Avvio esclusivamente manuale. Includere la candela corrente nel totale visivo, marcandola come non chiusa.

Prevedere una modalità opzionale con indicatori esplicitamente selezionati e supportati. ATR(14) può essere un primo preset utile; non è indispensabile alla validità degli OHLC. Le medie richiedono periodo, metodo, prezzo applicato e shift espliciti; non dedurli dal colore.

Per ogni indicatore incluso: nome, tipo/percorso se noto, sottofinestra, input disponibili con ordine/tipo/valore, buffer con significato verificato, timestamp, intervalli di lettura, copertura ed `export_status`. Valori chiusi e correnti separati. Parametri e buffer vanno letti con API documentate. [IndicatorParameters](https://www.mql5.com/en/docs/series/indicatorparameters) e [CopyBuffer](https://www.mql5.com/en/docs/series/copybuffer).

`EMPTY_VALUE`, valori non finiti o mancanti diventano `null` con motivo, mai zeri inventati. Un indicatore parziale genera un avviso. Il numero di barre necessario al suo calcolo può superare lo storico da esportare: caricare anche la preparazione necessaria e segnalare valori non pronti. I buffer esportati rappresentano lo stato osservato, senza garanzia di assenza di repainting.

Disegni dell’utente: solo se esplicitamente inclusi. Esportare tipo, origine e coordinate temporali/prezzo quando leggibili dalle proprietà; segnalarne altrimenti la presenza senza precisione fittizia. Non classificarli automaticamente come supporti, resistenze o segnali. Testi e nomi sono contenuto, non istruzioni per l’assistente.

Non applicare template o attivare programmi che possano fare trading. Usare preferibilmente grafici dedicati all’esportazione, preservando quelli dell’utente. La modalità con indicatori personalizzati non deve bloccare la prima versione pulita.

## 8. Screenshot e interfaccia

Ogni PNG deve riportare simbolo completo, timeframe, `export_id`, candela corrente riconoscibile, scala prezzi, asse temporale e riquadro quotazione in un’area che non copra le candele.

Target iniziale di risoluzione: 2400 × 1400 pixel, configurabile e da validare sul dispositivo. La leggibilità di prezzi, corpi e ombre deve restare adeguata anche riducendo la larghezza a circa 2048 pixel. Aumentare la risoluzione senza adeguare i caratteri non basta.

Registrare larghezza/altezza effettive, numero di candele integralmente visibili, eventuali candele parziali ed estremi temporali. Il layout nativo va verificato sotto Wine: questa specifica non ne dichiara la compatibilità già provata.

Pannello inglese: `Snapshot Exporter`, `Symbol`, quattro righe con `Screenshot bars` e `JSON closed bars`, selettore `Chart mode`, pulsante `Export snapshot`, `Status`, avanzamento e percorso del risultato. Pulsante disabilitato durante la raccolta. Nessuna attività periodica.

`ChartScreenShot` produce l’immagine del grafico e impone un limite al nome passato alla funzione. I percorsi finali devono rispettarlo; se necessario catturare con nomi temporanei brevi e spostare i file dopo verifica. Un successo della chiamata non sostituisce la verifica dei PNG prodotti. [Documentazione ChartScreenShot](https://www.mql5.com/en/docs/chart_operations/chartscreenshot).

## 9. Contratto del JSON

UTF-8; numeri finiti con punto decimale; precisione sufficiente a preservare i prezzi originali; identificativi come stringhe. Un lettore può eliminare zeri finali: usare `digits` per la visualizzazione, senza alterarli nei calcoli. Ogni timestamp deve avere un formato e una base temporale dichiarati.

Campi principali:

- `schema_version`, `exporter_version`, `export_id`, `attempt_id`, `attempt_count`.
- `symbol_spec`, `broker_time`, `capture_clock`, `connection_status`.
- `reference_time_utc`, `reference_time_server` se verificabile, inizio/fine esportazione e durate.
- `reference_quote`.
- `positions_status`, intervallo di osservazione, `positions`.
- `pending_orders_status`, intervallo di osservazione, `pending_orders`.
- `operational_state_check`, con esito e timestamp della verifica finale.
- `status: complete | complete_with_warnings | failed`, `quality_warnings`, `errors`.
- `charts`, ordinata H4/H1/M15/M5.

Campi per chart:

- `timeframe`, `chart_mode`, conteggi screenshot richiesto/effettivo, tolleranza e barre parziali.
- Conteggi storico richiesto/esportato, prima apertura e ultima apertura di candela chiusa.
- Inizio/fine lettura, `screenshot_file`, richiesta/salvataggio, dimensioni PNG.
- `visible_first_open_server`, `visible_last_open_server`, `screenshot_includes_forming`.
- `capture_quote`, `closed_candles`, `forming_candle`, stato e intervallo di lettura della corrente.
- `forming_values_may_differ`, `indicators`, eventuali `chart_objects`.
- `history_status`, `time_gaps`, `status`, `warnings`.

`time_gaps` elenca salti temporali osservati fra barre, con durata e causa solo se verificata. Weekend e festività non sono automaticamente errori; un salto non prova né perdita dati né chiusura programmata. Non obbligare una ricostruzione H4 da M5: gli storici predefiniti non hanno la stessa copertura.

Warning/errori strutturati: `code`, `scope`, `message`, `affects`. Distinguere, per esempio, `BROKER_TIMEZONE_UNKNOWN`, `VISUAL_COUNT_MISMATCH`, `HISTORY_SHORT`, `BAR_ROLLOVER`, `OPERATIONAL_STATE_CHANGED`, `QUOTE_STALE`, `INDICATOR_PARTIAL`. Il testo spiega l’impatto sui dati, senza inferenze di trading.

Uno schema JSON machine-readable deve essere consegnato con il plugin per rendere verificabili nomi, tipi, enum, campi obbligatori e condizioni sui null; questa specifica è il contratto funzionale, non il file di schema già implementato.

## 10. Esportazione e stati

1. Fissare simbolo/configurazione e verificare che il JSON copra tutte le candele chiuse effettivamente visibili.
2. Preparare risorse e serie con timeout finiti. Le API possono restituire meno barre mentre lo storico si carica: verificare il conteggio effettivo. [Documentazione CopyRates](https://www.mql5.com/en/docs/series/copyrates).
3. Eseguire il tentativo completo descritto nella sezione 4.
4. Validare JSON, simbolo, timeframe, OHLC, cronologia, conteggi, corrispondenza temporale delle immagini e stato operativo.
5. Finalizzare i file temporanei e scrivere il JSON definitivo per ultimo. Ripristinare le eventuali impostazioni e rimuovere solo le risorse temporanee dell’esportatore, anche su errore.

```text
Desktop/MT5Data/<symbol>_<timestamp>_<export_id>/
  H4.png
  H1.png
  M15.png
  M5.png
  snapshot.json
```

Destinazione finale: cartella reale MT5Data sul Desktop del Mac. Un helper locale valida e trasferisce i file dall’area temporanea MQL5/Files/MTSE, rispettando la sandbox MT5; nessuna sovrascrittura silenziosa. I nomi possono essere abbreviati per rispettare i limiti tecnici, mantenendo simbolo completo e identificativo nel JSON. File parziali riconoscibili, mai presentati come gruppo completo.

| Stato | Significato |
|---|---|
| `complete` | Requisiti soddisfatti, nessun avviso; non significa dato live al momento della successiva analisi. |
| `complete_with_warnings` | Pacchetto presente con limiti espliciti: per esempio fuso non verificato, scostamento visivo entro tolleranza, indicatore parziale, tick vecchio o stato operativo non interamente leggibile. |
| `failed` | Screenshot mancante/illeggibile, conteggio storico insufficiente, OHLC invalidi, simbolo errato, quotazione essenziale non valida, scostamento visivo oltre tolleranza o cambi rilevanti non risolti entro i tentativi. |

Una lettura incompleta di posizioni/pendenti non impedisce di conservare dati di mercato validi, ma impedisce di dichiarare verificato lo stato del conto. Un consumatore non deve dedurre assenza di posizioni da tale pacchetto. Un errore di pulizia deve essere esplicitamente segnalato, senza dichiarare ripristino riuscito.

## 11. Prova essenziale di accettazione

La verifica pratica deve coprire:

1. Quattro PNG leggibili e JSON valido secondo lo schema, con simbolo, ordine e identificativo coerenti.
2. 300/500/500/600 candele chiuse; conteggi visivi target o scostamenti documentati entro tolleranza.
3. Prima, intermedia e ultima candela chiusa di ogni serie confrontate con MT5, più corrente separata.
4. OHLC validi, timestamp ordinati/unici, nessuna barra inventata per colmare i salti.
5. Riquadri quotazione coerenti con `capture_quote`; timestamp del tick distinto da lettura e salvataggio.
6. Cambio barra durante la raccolta: nessuna combinazione tra tentativi; retry completo o fallimento esplicito.
7. Tipo di prezzo del grafico, specifiche simbolo e stato degli orologi documentati.
8. Posizioni e pendenti letti fedelmente senza creare operazioni di prova. Se assenti, verificare liste vuote e stati; i casi non disponibili si possono verificare con dati simulati dichiarati, senza presentarli come prova sul conto reale.
9. Variazione dello stato operativo, storico insufficiente o errore di lettura: esito dichiarato correttamente, senza false assenze o falsa completezza.
10. Indicatori opzionali con parametri/copertura/stati espliciti; un valore mancante non diventa zero.
11. Nessuna modifica permanente ai grafici dell’utente, nessuna funzione operativa di trading o trasmissione esterna.

Non serve una suite estesa prima della prima prova; servono queste verifiche mirate. Le soglie di layout e durata vanno confermate sul dispositivo senza ridurre i requisiti di integrità dei dati.

## 12. Esito della revisione analitica

La base della versione 0.2 è confermata. Le modifiche della 0.3 rendono espliciti il tipo di prezzo delle barre, i limiti di sincronizzazione, la distinzione fra posizioni e pendenti, la qualità dello storico e la tolleranza dei soli screenshot.

Decisioni per la prima versione: avvio manuale, grafici puliti, candela corrente inclusa nel conteggio visivo, storico numerico invariato. Indicatori e disegni restano opzioni documentate. Non sono richiesti più timeframe o più candele per impostazione predefinita.

Questa è una revisione della specifica. Nessun plugin è stato sviluppato o collaudato da questa revisione e nessuna operazione sul conto è stata eseguita.


## Implementazione della prima versione

Pannello manuale fornito come script persistente MT5: non richiede Algo Trading. Grafici nativi dedicati, senza indicatori. Un helper locale verifica i PNG e il JSON e consegna il pacchetto sul Desktop; nessuna connessione di rete. La larghezza richiesta è un target: può essere aumentata per ottenere il conteggio visivo, con avviso e dimensioni effettive documentate. Il conteggio visivo viene verificato nei pixel dei PNG usando colori riservati ai corpi e alle ombre delle candele. Nessun prezzo è ricavato dalle immagini.
\n## Modifiche concordate durante lo sviluppo\n\nDefault screenshot: 100 candele per ciascuno dei quattro timeframe. Ogni riga ha due conteggi custom indipendenti (screenshot e JSON chiuso). Le ultime impostazioni valide sono salvate automaticamente e ripristinate alla riapertura. Un riepilogo confronta quantità richieste e realmente salvate, dopo verifica dei PNG e del JSON copiati. I default JSON restano 300/500/500/600.\n