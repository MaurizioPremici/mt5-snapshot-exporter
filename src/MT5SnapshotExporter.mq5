#property strict
#property version "1.02"
#property script_show_inputs
#property description "Manual, read-only snapshots. Four native charts and one verified JSON."
#include "SnapshotData.mqh"
int panel_events=INVALID_HANDLE;
input int ScreenshotWidth=2400;
input int ScreenshotHeight=1400;
input double RightMarginPercent=12.5; // Native right margin, 10-15 percent
input int ScreenshotTolerance=5;
input int MaxAttempts=3;
input int SnapshotWarningSeconds=10;
input int HistoryTimeoutSeconds=45;
Frame frames[4];long owner;string prefix="",job="",stage="",error_text="",export_symbol="",last_prefs="";double export_point=0;int digits=0;double dpi=1;
string export_started,reference_time,reference_quote,positions,orders,positions_status,orders_status,operation_start,operation_end,final_check_time;
string warnings="",errors="",symbol_spec="";bool connected_start=false,connected_end=false;int attempt=0;ulong window_ms=0,collection_ms=0;

void UI(string id,ENUM_OBJECT type,int x,int y,int w,int h,string text,color bg=C'17,26,35',int font=10){
 string n=prefix+id;ObjectCreate(owner,n,type,0,0,0);
 ObjectSetInteger(owner,n,OBJPROP_XDISTANCE,(int)(x*dpi));ObjectSetInteger(owner,n,OBJPROP_YDISTANCE,(int)(y*dpi));
 ObjectSetInteger(owner,n,OBJPROP_XSIZE,(int)(w*dpi));ObjectSetInteger(owner,n,OBJPROP_YSIZE,(int)(h*dpi));
 ObjectSetInteger(owner,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);ObjectSetInteger(owner,n,OBJPROP_COLOR,clrWhiteSmoke);
 ObjectSetInteger(owner,n,OBJPROP_BGCOLOR,bg);ObjectSetInteger(owner,n,OBJPROP_BORDER_COLOR,C'48,65,82');
 ObjectSetInteger(owner,n,OBJPROP_FONTSIZE,font);ObjectSetInteger(owner,n,OBJPROP_SELECTABLE,false);ObjectSetInteger(owner,n,OBJPROP_HIDDEN,true);
 ObjectSetInteger(owner,n,OBJPROP_ZORDER,type==OBJ_RECTANGLE_LABEL?0:5);ObjectSetString(owner,n,OBJPROP_FONT,"Arial");ObjectSetString(owner,n,OBJPROP_TEXT,text);
}
void Status(string text){WriteText("MTSE\\last_status.txt",text);ObjectSetString(owner,prefix+"status",OBJPROP_TEXT,text);ChartRedraw(owner);Print("Snapshot Exporter: ",text);}
void Panel(){
 UI("bg",OBJ_RECTANGLE_LABEL,20,45,550,385,"");UI("title",OBJ_LABEL,34,58,0,0,"Snapshot Exporter  |  "+export_symbol,C'17,26,35',13);
 UI("head",OBJ_LABEL,34,93,0,0,"Timeframe       Screenshot candles       JSON closed candles");
 for(int i=0;i<4;i++){int y=119+35*i;UI("tf"+I(i),OBJ_LABEL,36,y+5,0,0,frames[i].name);UI("s"+I(i),OBJ_EDIT,155,y,120,29,I(frames[i].screen_count));UI("j"+I(i),OBJ_EDIT,333,y,150,29,I(frames[i].history_count));}
 UI("mode",OBJ_LABEL,34,266,0,0,"Clean native charts | Current candle included in screenshots",C'17,26,35',9);
 UI("export",OBJ_BUTTON,34,293,515,34,"Export snapshot",C'27,109,200',11);
 UI("min",OBJ_BUTTON,486,51,32,30,"-");UI("close",OBJ_BUTTON,526,51,32,30,"x");
 UI("open",OBJ_BUTTON,200,8,160,30,"Snapshot Exporter");ObjectSetInteger(owner,prefix+"open",OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
 UI("status",OBJ_LABEL,34,341,0,0,"Ready | Desktop/MT5Data",C'17,26,35',9);
 UI("counts",OBJ_LABEL,34,368,0,0,"Settings are saved automatically",C'17,26,35',9);UI("counts2",OBJ_LABEL,34,391,0,0," ",C'17,26,35',9);ChartRedraw(owner);
}
bool IntegerText(string s,int &v){if(StringLen(s)<1||StringLen(s)>6)return false;for(int k=0;k<StringLen(s);k++){ushort c=StringGetCharacter(s,k);if(c<48||c>57)return false;}v=(int)StringToInteger(s);return true;}
bool Config(bool show_error=true){
 int ss[4],jj[4];
 for(int i=0;i<4;i++){
 if(!IntegerText(ObjectGetString(owner,prefix+"s"+I(i),OBJPROP_TEXT),ss[i])||!IntegerText(ObjectGetString(owner,prefix+"j"+I(i),OBJPROP_TEXT),jj[i])||ss[i]<20||ss[i]>500||jj[i]<ss[i]||jj[i]>10000){if(show_error)Status("Use 20-500 image candles; JSON >= image, up to 10000");return false;}
 }
 string prefs="";for(int i=0;i<4;i++){frames[i].screen_count=ss[i];frames[i].history_count=jj[i];prefs+=I(ss[i])+" "+I(jj[i])+" ";}
 if(prefs!=last_prefs){if(!WriteText("MTSE\\preferences.txt",prefs)){if(show_error)Status("Could not save preferences");return false;}last_prefs=prefs;}
 return true;
}
string WaitText(string path,int ms){ulong start=GetTickCount64();while(!IsStopped()&&GetTickCount64()-start<(ulong)ms){string s=ReadText(path);if(s!="")return s;Sleep(100);}return "";}
bool PNG(long c,string file,int width){
 FileDelete(file);ChartRedraw(c);if(!ChartScreenShot(c,file,width,ScreenshotHeight,ALIGN_RIGHT)){error_text="ChartScreenShot failed: "+I(GetLastError());return false;}
 ulong start=GetTickCount64(),last=0;int stable=0;
 while(!IsStopped()&&GetTickCount64()-start<8000){Sleep(100);int f=FileOpen(file,FILE_READ|FILE_BIN|FILE_SHARE_READ);if(f==INVALID_HANDLE)continue;ulong size=FileSize(f);FileClose(f);if(size>1000&&size==last)stable++;else stable=0;last=size;if(stable>=2)return true;}
 error_text="Screenshot file was not completed";return false;
}
void Header(Frame &f,string line1,string line2,string line3){
 string lines[3];lines[0]=line1;lines[1]=line2;lines[2]=line3;
 for(int i=0;i<3;i++){string n="MTSE_header"+I(i);ObjectCreate(f.chart,n,OBJ_LABEL,0,0,0);ObjectSetInteger(f.chart,n,OBJPROP_XDISTANCE,22);ObjectSetInteger(f.chart,n,OBJPROP_YDISTANCE,18+i*44);ObjectSetInteger(f.chart,n,OBJPROP_FONTSIZE,i==0?16:12);ObjectSetInteger(f.chart,n,OBJPROP_COLOR,clrWhiteSmoke);ObjectSetString(f.chart,n,OBJPROP_FONT,"Arial");ObjectSetString(f.chart,n,OBJPROP_TEXT,lines[i]);ObjectSetInteger(f.chart,n,OBJPROP_SELECTABLE,false);}
}
void CaptureAnnotations(Frame &f,const MqlTick &quote){
 color accent=C'139,181,255',marker=C'255,209,102';
 string line="MTSE_frozen_bid";
 ObjectCreate(f.chart,line,OBJ_HLINE,0,0,quote.bid);ObjectSetDouble(f.chart,line,OBJPROP_PRICE,quote.bid);
 ObjectSetInteger(f.chart,line,OBJPROP_COLOR,accent);ObjectSetInteger(f.chart,line,OBJPROP_STYLE,STYLE_DASH);
 ObjectSetInteger(f.chart,line,OBJPROP_WIDTH,1);
 ObjectSetInteger(f.chart,line,OBJPROP_SELECTABLE,false);ObjectSetInteger(f.chart,line,OBJPROP_BACK,true);
 ObjectSetString(f.chart,line,OBJPROP_TEXT,"Frozen capture Bid");
 // Native pixel label on the exported price scale; the quote never follows ticks.
 double maximum=ChartGetDouble(f.chart,CHART_FIXED_MAX),minimum=ChartGetDouble(f.chart,CHART_FIXED_MIN);
 int py=(int)MathRound((maximum-quote.bid)/(maximum-minimum)*f.plot_bottom);
 string box="MTSE_price_box",value="MTSE_price_value";
 int tag_width=MathMax(90,(digits+3)*14);
 ObjectCreate(f.chart,box,OBJ_RECTANGLE_LABEL,0,0,0);
 ObjectSetInteger(f.chart,box,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
 ObjectSetInteger(f.chart,box,OBJPROP_XDISTANCE,tag_width);ObjectSetInteger(f.chart,box,OBJPROP_YDISTANCE,py-15);
 ObjectSetInteger(f.chart,box,OBJPROP_XSIZE,tag_width-2);ObjectSetInteger(f.chart,box,OBJPROP_YSIZE,30);
 ObjectSetInteger(f.chart,box,OBJPROP_BGCOLOR,accent);ObjectSetInteger(f.chart,box,OBJPROP_BORDER_TYPE,BORDER_FLAT);
 ObjectSetInteger(f.chart,box,OBJPROP_COLOR,accent);ObjectSetInteger(f.chart,box,OBJPROP_SELECTABLE,false);
 ObjectCreate(f.chart,value,OBJ_LABEL,0,0,0);ObjectSetInteger(f.chart,value,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
 ObjectSetInteger(f.chart,value,OBJPROP_ANCHOR,ANCHOR_RIGHT);ObjectSetInteger(f.chart,value,OBJPROP_XDISTANCE,5);
 ObjectSetInteger(f.chart,value,OBJPROP_YDISTANCE,py);ObjectSetInteger(f.chart,value,OBJPROP_FONTSIZE,10);
 ObjectSetInteger(f.chart,value,OBJPROP_COLOR,C'15,23,32');ObjectSetString(f.chart,value,OBJPROP_FONT,"Arial");
 ObjectSetString(f.chart,value,OBJPROP_TEXT,DoubleToString(quote.bid,digits));ObjectSetInteger(f.chart,value,OBJPROP_SELECTABLE,false);

 string tag="MTSE_frozen_caption";
 datetime right=f.identity+PeriodSeconds(f.tf)*2;
 double caption_price=quote.bid+(maximum-minimum)*.015;
 ObjectCreate(f.chart,tag,OBJ_TEXT,0,right,caption_price);ObjectMove(f.chart,tag,0,right,caption_price);
 ObjectSetString(f.chart,tag,OBJPROP_TEXT,"Frozen Bid");ObjectSetString(f.chart,tag,OBJPROP_FONT,"Arial");
 ObjectSetInteger(f.chart,tag,OBJPROP_FONTSIZE,9);ObjectSetInteger(f.chart,tag,OBJPROP_COLOR,accent);
 ObjectSetInteger(f.chart,tag,OBJPROP_ANCHOR,ANCHOR_LEFT_LOWER);ObjectSetInteger(f.chart,tag,OBJPROP_SELECTABLE,false);
 double span=ChartGetDouble(f.chart,CHART_FIXED_MAX)-ChartGetDouble(f.chart,CHART_FIXED_MIN);
 double top=f.rates[f.history_count].high+span*.015;
 string arrow="MTSE_forming_arrow",label="MTSE_forming_label";
 ObjectCreate(f.chart,arrow,OBJ_ARROW_DOWN,0,f.identity,top);ObjectMove(f.chart,arrow,0,f.identity,top);
 ObjectSetInteger(f.chart,arrow,OBJPROP_COLOR,marker);ObjectSetInteger(f.chart,arrow,OBJPROP_WIDTH,1);
 ObjectSetInteger(f.chart,arrow,OBJPROP_ANCHOR,ANCHOR_BOTTOM);ObjectSetInteger(f.chart,arrow,OBJPROP_SELECTABLE,false);
 ObjectCreate(f.chart,label,OBJ_TEXT,0,right,top+span*.018);ObjectMove(f.chart,label,0,right,top+span*.018);
 ObjectSetString(f.chart,label,OBJPROP_TEXT,"Forming");ObjectSetString(f.chart,label,OBJPROP_FONT,"Arial");
 ObjectSetInteger(f.chart,label,OBJPROP_FONTSIZE,9);ObjectSetInteger(f.chart,label,OBJPROP_COLOR,marker);
 ObjectSetInteger(f.chart,label,OBJPROP_ANCHOR,ANCHOR_LEFT_LOWER);ObjectSetInteger(f.chart,label,OBJPROP_SELECTABLE,false);
}
bool Layout(Frame &f){
 MqlRates rates[];if(CopyRates(export_symbol,f.tf,0,f.screen_count+ScreenshotTolerance+2,rates)<f.screen_count+ScreenshotTolerance+2){error_text="History is not ready for chart layout";return false;}
 double low=DBL_MAX,high=-DBL_MAX;for(int i=0;i<ArraySize(rates);i++){low=MathMin(low,rates[i].low);high=MathMax(high,rates[i].high);}double span=MathMax(high-low,export_point*100);
 ChartSetInteger(f.chart,CHART_SCALEFIX,true);ChartSetDouble(f.chart,CHART_FIXED_MIN,low-span*.08);ChartSetDouble(f.chart,CHART_FIXED_MAX,high+span*.25);
 ChartSetInteger(f.chart,CHART_AUTOSCROLL,true);ChartSetInteger(f.chart,CHART_SCALE,f.chart_scale);
 ChartSetInteger(f.chart,CHART_SHIFT,f.shift>=10);if(f.shift>=10)ChartSetDouble(f.chart,CHART_SHIFT_SIZE,f.shift);
 ChartNavigate(f.chart,CHART_END,0);ChartRedraw(f.chart);return true;
}
bool ConfigureChart(Frame &f){
 f.chart=ChartOpen(export_symbol,f.tf);if(f.chart==0){error_text="Could not create export chart";return false;}Sleep(250);
 if(StringLen(ChartGetString(f.chart,CHART_EXPERT_NAME))>0||StringLen(ChartGetString(f.chart,CHART_SCRIPT_NAME))>0){error_text="Unexpected program: expert=["+ChartGetString(f.chart,CHART_EXPERT_NAME)+"] script=["+ChartGetString(f.chart,CHART_SCRIPT_NAME)+"] owner="+I(owner)+" new="+I(f.chart);return false;}
 ChartSetInteger(f.chart,CHART_SHOW_TRADE_HISTORY,false);ChartSetInteger(f.chart,CHART_SHOW_TRADE_LEVELS,false);ChartSetInteger(f.chart,CHART_DRAG_TRADE_LEVELS,false);ChartSetInteger(f.chart,CHART_SHOW_ONE_CLICK,false);
 int windows=(int)ChartGetInteger(f.chart,CHART_WINDOWS_TOTAL);
 for(int w=windows-1;w>=0;w--)for(int j=ChartIndicatorsTotal(f.chart,w)-1;j>=0;j--)if(!ChartIndicatorDelete(f.chart,w,ChartIndicatorName(f.chart,w,j))){error_text="Could not remove a default indicator";return false;}
 ObjectsDeleteAll(f.chart);ChartSetInteger(f.chart,CHART_MODE,CHART_CANDLES);ChartSetInteger(f.chart,CHART_FOREGROUND,false);
 ChartSetInteger(f.chart,CHART_SHOW_GRID,false);ChartSetInteger(f.chart,CHART_SHOW_OHLC,false);ChartSetInteger(f.chart,CHART_SHOW_BID_LINE,false);ChartSetInteger(f.chart,CHART_SHOW_ASK_LINE,false);ChartSetInteger(f.chart,CHART_SHOW_LAST_LINE,false);ChartSetInteger(f.chart,CHART_SHOW_VOLUMES,CHART_VOLUME_HIDE);ChartSetInteger(f.chart,CHART_SHOW_PERIOD_SEP,false);
 ChartSetInteger(f.chart,CHART_SHOW_DATE_SCALE,true);ChartSetInteger(f.chart,CHART_SHOW_PRICE_SCALE,true);ChartSetInteger(f.chart,CHART_SHOW_TICKER,false);
 ChartSetInteger(f.chart,CHART_COLOR_BACKGROUND,C'15,23,32');ChartSetInteger(f.chart,CHART_COLOR_FOREGROUND,C'188,199,214');
 ChartSetInteger(f.chart,CHART_COLOR_CHART_LINE,C'45,212,191');
 ChartSetInteger(f.chart,CHART_COLOR_CHART_UP,C'45,212,191');ChartSetInteger(f.chart,CHART_COLOR_CANDLE_BULL,C'45,212,191');ChartSetInteger(f.chart,CHART_COLOR_CHART_DOWN,C'248,113,113');ChartSetInteger(f.chart,CHART_COLOR_CANDLE_BEAR,C'248,113,113');
 f.shift=RightMarginPercent;f.chart_scale=f.screen_count<40?5:4;f.spacing=f.chart_scale==5?32:16;
 f.width=(int)MathMax(800,MathRound((f.screen_count*f.spacing+70)/(1.0-f.shift/100.0)));
 Header(f,export_symbol+" | "+f.name+" | Layout calibration","Preparing native chart","Current candle is not closed");
 for(int pass=0;pass<5;pass++){
 if(!Layout(f))return false;Sleep(200);string file=stage+"\\cal"+f.name+"_"+I(pass);FileDelete(file+".count");FileDelete(file+".inspect");
 if(!PNG(f.chart,file+".png",f.width))return false;
 if(!WriteText(file+".inspect","inspect")){error_text="Could not request image verification";return false;}
 string result=WaitText(file+".count",12000);if(StringFind(result,"OK ")!=0){error_text="Image verification: "+result;return false;}
 string pieces[];StringSplit(result,' ',pieces);if(ArraySize(pieces)<6){error_text="Invalid image verification reply";return false;}
 f.plot_bottom=(int)StringToInteger(pieces[5]);if(f.plot_bottom<1){error_text="Native price scale could not be located";return false;}
 f.actual=(int)StringToInteger(pieces[1]);f.partial=(int)StringToInteger(pieces[2]);int delta=f.screen_count-f.actual;
 if(f.actual>f.history_count+1){error_text="Visual interval exceeds JSON history";return false;}
 if(delta==0)return true;
 if(pass==4){if(MathAbs(delta)<=ScreenshotTolerance)return true;error_text="Native image count outside tolerance";return false;}
 f.width+=(int)MathRound(delta*(double)f.spacing/(1.0-f.shift/100.0));if(f.width<800||f.width>12000){error_text="Unsupported native screenshot dimensions";return false;}
 }
 return false;
}
bool Cleanup(){bool ok=true;for(int i=0;i<4;i++)if(frames[i].chart!=0){if(!ChartClose(frames[i].chart))ok=false;frames[i].chart=0;}ChartSetInteger(owner,CHART_BRING_TO_TOP,true);return ok;}
bool SymbolSpec(){
 long dg,mode,custom,stops,freeze;double ticksize,contract;
 if(!SymbolInfoInteger(export_symbol,SYMBOL_DIGITS,dg)||!SymbolInfoDouble(export_symbol,SYMBOL_POINT,export_point)||!SymbolInfoDouble(export_symbol,SYMBOL_TRADE_TICK_SIZE,ticksize)||!SymbolInfoDouble(export_symbol,SYMBOL_TRADE_CONTRACT_SIZE,contract)||export_point<=0||ticksize<=0||contract<=0)return false;
 digits=(int)dg;price_digits=digits;bool known=SymbolInfoInteger(export_symbol,SYMBOL_CHART_MODE,mode);string basis=known?(mode==SYMBOL_CHART_MODE_BID?"bid":(mode==SYMBOL_CHART_MODE_LAST?"last":"unknown")):"unknown";
 bool c=SymbolInfoInteger(export_symbol,SYMBOL_CUSTOM,custom),s=SymbolInfoInteger(export_symbol,SYMBOL_TRADE_STOPS_LEVEL,stops),z=SymbolInfoInteger(export_symbol,SYMBOL_TRADE_FREEZE_LEVEL,freeze);
 symbol_spec="{\"symbol\":"+Q(export_symbol)+",\"digits\":"+I(dg)+",\"point\":"+N(export_point)+",\"tick_size\":"+N(ticksize)+",\"contract_size\":"+N(contract)+",\"chart_price_basis\":"+Q(basis)+",\"is_custom\":"+(c?B(custom!=0):"null")+",\"stops_level_points\":"+(s?I(stops):"null")+",\"freeze_level_points\":"+(z?I(freeze):"null")+"}";return true;
}
bool Prepare(){
 if(!SymbolSpec()){error_text="Required symbol properties unavailable";return false;}
 string pre="MTSE\\"+job;
 if(!WriteText(pre+".preflight","check")){error_text="Could not contact Desktop helper";return false;}
 string allowed=WaitText(pre+".allow",6000);FileDelete(pre+".preflight");FileDelete(pre+".allow");if(allowed!="OK"){error_text=allowed==""?"Desktop helper is not running":allowed;return false;}
 ulong started=GetTickCount64();bool loaded=false;
 while(!IsStopped()&&GetTickCount64()-started<(ulong)HistoryTimeoutSeconds*1000){loaded=true;for(int i=0;i<4;i++){MqlRates r[];if(CopyRates(export_symbol,frames[i].tf,0,frames[i].history_count+1,r)!=frames[i].history_count+1)loaded=false;}if(loaded)break;Sleep(250);}
 if(!loaded){error_text="HISTORY_SHORT: required closed candles not available";return false;}
 for(int i=0;i<4;i++){Status("Preparing "+frames[i].name+" | verifying native candle count");if(!ConfigureChart(frames[i]))return false;}
 return true;
}
bool Attempt(bool &retry){
 retry=false;for(int k=0;k<4;k++)FileDelete(stage+"\\"+frames[k].name+".png");ulong start=GetTickCount64();connected_start=(bool)TerminalInfoInteger(TERMINAL_CONNECTED);
 for(int i=0;i<4;i++){frames[i].identity=iTime(export_symbol,frames[i].tf,0);if(frames[i].identity<=0){error_text="Current bar unavailable";return false;}}
 reference_time=UTC();MqlTick tick;reference_quote=QuoteRead(export_symbol,export_point,tick);if(reference_quote==""){error_text="Invalid reference quote";return false;}
 operation_start=UTC();positions=PositionsRead(export_symbol,positions_status);orders=OrdersRead(export_symbol,orders_status);operation_end=UTC();
 for(int i=0;i<4;i++)if(!ReadFrame(export_symbol,frames[i])){retry=true;error_text="History changed or invalid OHLC during collection";return false;}
 collection_ms=GetTickCount64()-start;
 for(int i=0;i<4;i++){
  Status("Capturing "+frames[i].name+" | attempt "+I(attempt));
  ChartSetInteger(frames[i].chart,CHART_BRING_TO_TOP,true);if(!Layout(frames[i]))return false;
  frames[i].capture_quote=QuoteRead(export_symbol,export_point,tick);if(frames[i].capture_quote==""){error_text="Invalid capture quote";return false;}
  Header(frames[i],export_symbol+"  |  "+frames[i].name+"  |  Export "+job+" / "+I(attempt),"Bid "+DoubleToString(tick.bid,digits)+"  Ask "+DoubleToString(tick.ask,digits)+" | Tick "+TS(tick.time),"UTC "+quote_read_completed+" | "+I(frames[i].actual)+" bars; last forming");
  CaptureAnnotations(frames[i],tick);
  frames[i].capture_start=UTC();ulong captured=GetTickCount64();if(!PNG(frames[i].chart,stage+"\\"+frames[i].name+".png",frames[i].width))return false;frames[i].capture_end=UTC();frames[i].capture_duration=GetTickCount64()-captured;
 }
 bool rollover=false;
 string ps,os;string p=PositionsRead(export_symbol,ps),o=OrdersRead(export_symbol,os);final_check_time=UTC();connected_end=(bool)TerminalInfoInteger(TERMINAL_CONNECTED);window_ms=GetTickCount64()-start;
 for(int i=0;i<4;i++)if(frames[i].identity!=iTime(export_symbol,frames[i].tf,0))rollover=true;
 if(rollover){retry=true;error_text="BAR_ROLLOVER: current bar changed; whole group discarded";return false;}
 if(p!=positions||o!=orders||ps!=positions_status||os!=orders_status){retry=true;error_text="OPERATIONAL_STATE_CHANGED: whole group discarded";return false;}
 if(ps!="success"||os!="success")Append(warnings,Issue("OPERATIONAL_STATE_PARTIAL","symbol","Some operational properties could not be read; empty arrays do not establish absence","positions_and_pending_orders"));
 return true;
}
string Package(bool success){
 string charts="";if(success)for(int i=0;i<4;i++)Append(charts,FrameJSON(frames[i],ScreenshotHeight,ScreenshotTolerance));
 string check=(positions_status=="success"&&orders_status=="success")?"unchanged":"unverifiable";
 string result="{\"schema_version\":\"1.0\",\"exporter_version\":\"1.2.0\",\"export_id\":"+Q(job)+",\"attempt_id\":"+Q(job+"-"+I(attempt))+",\"attempt_count\":"+I(attempt);
 result+=",\"symbol_spec\":"+(symbol_spec==""?"{\"symbol\":"+Q(export_symbol)+"}":symbol_spec);
 result+=",\"broker_time\":{\"time_basis\":\"broker_server\",\"timezone_name\":null,\"utc_offset_seconds_at_reference\":null,\"source\":\"not configured or verified\",\"status\":\"unavailable\"}";
 result+=",\"capture_clock\":{\"utc_source\":\"MQL5 TimeGMT / device clock\",\"verification_status\":\"unverified\",\"duration_source\":\"GetTickCount64 monotonic milliseconds\",\"server_timestamp_format\":\"YYYY-MM-DDTHH:mm:ss, broker server, no UTC conversion\",\"utc_resolution_seconds\":1}";
 result+=",\"connection_status\":{\"connected_at_reference\":"+B(connected_start)+",\"connected_at_completion\":"+B(connected_end)+"}";
 result+=",\"reference_time_utc\":"+(reference_time==""?"null":Q(reference_time))+",\"reference_time_server\":null,\"export_started_at_utc\":"+Q(export_started)+",\"export_completed_at_utc\":"+Q(UTC());
 result+=",\"snapshot_window_ms\":"+I((long)window_ms)+",\"data_collection_duration_ms\":"+I((long)collection_ms)+",\"reference_quote\":"+(reference_quote==""?"null":reference_quote);
 result+=",\"positions_status\":"+Q(positions_status)+",\"positions_observation\":{\"started_at_utc\":"+Q(operation_start)+",\"completed_at_utc\":"+Q(operation_end)+"},\"positions\":"+positions;
 result+=",\"pending_orders_status\":"+Q(orders_status)+",\"pending_orders_observation\":{\"started_at_utc\":"+Q(operation_start)+",\"completed_at_utc\":"+Q(operation_end)+"},\"pending_orders\":"+orders;
 result+=",\"operational_state_check\":{\"result\":"+Q(success?check:"not_verified")+",\"completed_at_utc\":"+Q(final_check_time)+",\"comparison\":\"Full serialised operational properties; excludes floating profit and current quote\",\"limit\":\"Matching endpoints do not prove absence of intermediate changes\"}";
 result+=",\"status\":"+Q(success?"complete_with_warnings":"failed")+",\"quality_warnings\":["+warnings+"],\"errors\":["+errors+"],\"charts\":["+charts+"]}";
 return result;
}
void Export(){
 if(!Config())return;
 ObjectSetString(owner,prefix+"counts2",OBJPROP_TEXT," ");
 export_started=UTC();reference_time="";reference_quote="";positions="[]";orders="[]";positions_status="error";orders_status="error";operation_start="";operation_end="";final_check_time="";symbol_spec="";warnings="";errors="";attempt=0;window_ms=0;collection_ms=0;error_text="";
 job=I((long)TimeLocal())+"_"+I((long)GetTickCount64());stage="MTSE\\"+job;
 if(!FolderCreate(stage)){Status("Could not create export staging folder");return;}
 ObjectSetString(owner,prefix+"export",OBJPROP_TEXT,"Exporting...");ObjectSetInteger(owner,prefix+"export",OBJPROP_STATE,false);
 bool success=Prepare();
 if(success){success=false;for(attempt=1;attempt<=MaxAttempts;attempt++){bool retry=false;if(Attempt(retry)){success=true;break;}if(!retry||IsStopped())break;Status("Retrying complete group: "+error_text);}}
 attempt=(int)MathMin(attempt,MaxAttempts);
 if(!Cleanup())Append(warnings,Issue("CLEANUP_FAILED","charts","A temporary chart could not be closed","workspace_cleanup"));
 Append(warnings,Issue("BROKER_TIMEZONE_UNKNOWN","time","Server timestamps are preserved; UTC conversion and tick age are unavailable","time_conversion_and_freshness"));
 Append(warnings,Issue("DEVICE_CLOCK_UNVERIFIED","time","Device UTC clock synchronisation was not independently verified","absolute_capture_time"));
 if(!connected_start||!connected_end)Append(warnings,Issue("TERMINAL_DISCONNECTED","connection","Terminal reports a disconnected endpoint; quote freshness is not established","freshness"));
 if(window_ms>(ulong)SnapshotWarningSeconds*1000)Append(warnings,Issue("SNAPSHOT_WINDOW_LONG","package","Sequential capture exceeded configured duration threshold","temporal_alignment"));
 if(success)for(int i=0;i<4;i++){if(frames[i].width!=ScreenshotWidth)Append(warnings,Issue("NATIVE_WIDTH_ADJUSTED",frames[i].name,"Native image width adjusted to preserve requested candle count","image_dimensions"));if(frames[i].actual!=frames[i].screen_count)Append(warnings,Issue("VISUAL_COUNT_MISMATCH",frames[i].name,"Actual visual count differs within tolerance","visual_count"));}
 if(!success){string code="EXPORT_FAILED";if(StringFind(error_text,"HISTORY_SHORT")==0)code="HISTORY_SHORT";if(StringFind(error_text,"BAR_ROLLOVER")==0)code="BAR_ROLLOVER";if(StringFind(error_text,"OPERATIONAL_STATE_CHANGED")==0)code="OPERATIONAL_STATE_CHANGED";Append(errors,Issue(code,"package",error_text,"package_integrity"));}
 if(!WriteText(stage+"\\snapshot.pending.json",Package(success))||!WriteText(stage+"\\ready","ready")){Status("Failed to write package; temporary files retained");return;}
 Status("Verifying saved images and JSON; copying to Desktop...");string result=WaitText(stage+"\\delivered.txt",30000);
 if(StringFind(result,"OK ")==0&&success){Status("Saved and verified | Desktop/MT5Data | warnings in JSON");string counts="Image/JSON: ",counts2="";for(int i=0;i<4;i++){string item=frames[i].name+" "+I(frames[i].actual)+"/"+I(frames[i].history_count)+"  ";if(i<2)counts+=item;else counts2+=item;}ObjectSetString(owner,prefix+"counts",OBJPROP_TEXT,counts);ObjectSetString(owner,prefix+"counts2",OBJPROP_TEXT,counts2);}
 else{Status(result==""?"Delivery pending: helper acknowledgement missing":result);ObjectSetString(owner,prefix+"counts",OBJPROP_TEXT,"Incomplete export: see snapshot.json errors");}
 ObjectSetString(owner,prefix+"export",OBJPROP_TEXT,"Export snapshot");ObjectSetInteger(owner,prefix+"export",OBJPROP_STATE,false);ChartRedraw(owner);
}
void OnStart(){
 if(RightMarginPercent<10||RightMarginPercent>15||ScreenshotWidth<800||ScreenshotWidth>12000||ScreenshotHeight<600||ScreenshotHeight>6000||ScreenshotTolerance<0||ScreenshotTolerance>20||MaxAttempts<1||MaxAttempts>5||HistoryTimeoutSeconds<1||SnapshotWarningSeconds<1){Alert("Invalid Snapshot Exporter inputs");return;}
 owner=ChartID();export_symbol=_Symbol;prefix="MTSE_"+I(owner)+"_";dpi=MathMax(1.0,(double)TerminalInfoInteger(TERMINAL_SCREEN_DPI)/96.0);
 frames[0].tf=PERIOD_H4;frames[0].name="H4";frames[0].history_count=300;
 frames[1].tf=PERIOD_H1;frames[1].name="H1";frames[1].history_count=500;
 frames[2].tf=PERIOD_M15;frames[2].name="M15";frames[2].history_count=500;
 frames[3].tf=PERIOD_M5;frames[3].name="M5";frames[3].history_count=600;
 FolderCreate("MTSE");string saved=ReadText("MTSE\\preferences.txt"),parts[];int n=StringSplit(saved,' ',parts);last_prefs=saved;
 for(int i=0;i<4;i++){frames[i].screen_count=100;frames[i].chart=0;if(n>=8){int s=(int)StringToInteger(parts[i*2]),j=(int)StringToInteger(parts[i*2+1]);if(s>=20&&s<=500&&j>=s&&j<=10000){frames[i].screen_count=s;frames[i].history_count=j;}}}
 for(int k=ChartIndicatorsTotal(owner,0)-1;k>=0;k--){string name=ChartIndicatorName(owner,0,k);if(name=="Snapshot panel controls"||name=="SnapshotPanelEvents"||name=="SnapshotPanelControls")ChartIndicatorDelete(owner,0,name);}
 Sleep(250);
 Panel();
 GlobalVariableSet(prefix+"request",0);GlobalVariableSet(prefix+"busy",0);GlobalVariableSet(prefix+"save",0);
 panel_events=iCustom(ChartSymbol(owner),ChartPeriod(owner),"\\Indicators\\MT5SnapshotExporter\\SnapshotPanelControls",owner,GetTickCount64());
 bool attached=false;int attach_error=GetLastError();
 if(panel_events!=INVALID_HANDLE)for(int tries=0;tries<20&&!IsStopped();tries++){Sleep(100);ResetLastError();if(ChartIndicatorAdd(owner,0,panel_events)){attached=true;break;}attach_error=GetLastError();}
 if(!attached){Status("Panel controls could not load: "+I(attach_error)+" handle="+I(panel_events)+" chart="+ChartSymbol(owner)+"/"+I(ChartPeriod(owner)));ObjectsDeleteAll(owner,prefix);if(panel_events!=INVALID_HANDLE)IndicatorRelease(panel_events);return;}
 ulong saved_at=0;
 while(!IsStopped()){
 if(GlobalVariableGet(prefix+"request")>0){
 GlobalVariableSet(prefix+"request",0);GlobalVariableSet(prefix+"busy",1);
 ObjectSetInteger(owner,prefix+"export",OBJPROP_STATE,false);
 ObjectSetInteger(owner,prefix+"export",OBJPROP_BGCOLOR,C'49,64,80');ObjectSetString(owner,prefix+"export",OBJPROP_TEXT,"Preparing...");ChartRedraw(owner);
 Export();
 GlobalVariableSet(prefix+"busy",0);ObjectSetInteger(owner,prefix+"export",OBJPROP_STATE,false);
 ObjectSetInteger(owner,prefix+"export",OBJPROP_BGCOLOR,C'27,109,200');ObjectSetString(owner,prefix+"export",OBJPROP_TEXT,"Export snapshot");ChartRedraw(owner);
 }
 if(GlobalVariableGet(prefix+"save")>0||GetTickCount64()-saved_at>1000){Config(false);GlobalVariableSet(prefix+"save",0);saved_at=GetTickCount64();}
 Sleep(20);
 }
 Cleanup();ChartIndicatorDelete(owner,0,"Snapshot panel controls");if(panel_events!=INVALID_HANDLE)IndicatorRelease(panel_events);
 GlobalVariableDel(prefix+"request");GlobalVariableDel(prefix+"busy");GlobalVariableDel(prefix+"save");
 ObjectsDeleteAll(owner,prefix);ChartRedraw(owner);
}
