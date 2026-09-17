#ifndef SNAPSHOT_DATA_MQH
#define SNAPSHOT_DATA_MQH
string Q(string s){StringReplace(s,"\\","\\\\");StringReplace(s,"\"","\\\"");StringReplace(s,"\r","\\r");StringReplace(s,"\n","\\n");StringReplace(s,"\t","\\t");return "\""+s+"\"";}
int price_digits=5;
string P(double v){return MathIsValidNumber(v)?DoubleToString(v,price_digits):"null";}
string N(double v){return MathIsValidNumber(v)?StringFormat("%.17g",v):"null";}
string I(long v){return StringFormat("%I64d",v);}
string B(bool v){return v?"true":"false";}
string TS(datetime t){string s=TimeToString(t,TIME_DATE|TIME_SECONDS);StringReplace(s,".","-");StringReplace(s," ","T");return s;}
string UTC(){return TS(TimeGMT())+"Z";}
string ST(long t){return t>0?Q(TS((datetime)t)):"null";}
string NullablePrice(double p){return p==0?"null":P(p);}
string Issue(string code,string scope,string message,string affects){return "{\"code\":"+Q(code)+",\"scope\":"+Q(scope)+",\"message\":"+Q(message)+",\"affects\":"+Q(affects)+"}";}
void Append(string &list,string value){if(list!="")list+=",";list+=value;}
bool WriteText(string name,string content){int f=FileOpen(name,FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);if(f==INVALID_HANDLE)return false;bool ok=FileWriteString(f,content)>0;FileFlush(f);FileClose(f);return ok;}
string ReadText(string name){int f=FileOpen(name,FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ,0,CP_UTF8);if(f==INVALID_HANDLE)return "";string s="";while(!FileIsEnding(f))s+=FileReadString(f);FileClose(f);return s;}
string quote_read_completed="";
string QuoteRead(string symbol,double point,MqlTick &tick){
 string started=UTC();if(!SymbolInfoTick(symbol,tick)||tick.bid<=0||tick.ask<tick.bid||tick.time_msc<=0||!MathIsValidNumber(tick.ask)||!MathIsValidNumber(tick.bid))return "";
 quote_read_completed=UTC();
 return "{\"bid\":"+P(tick.bid)+",\"ask\":"+P(tick.ask)+",\"spread_price\":"+P(tick.ask-tick.bid)+",\"spread_points\":"+DoubleToString((tick.ask-tick.bid)/point,6)+",\"tick_time_server\":"+ST(tick.time)+",\"tick_time_msc_raw\":"+I(tick.time_msc)+",\"tick_time_basis\":\"broker_server\",\"read_started_at_utc\":"+Q(started)+",\"read_completed_at_utc\":"+Q(quote_read_completed)+",\"tick_age_ms\":null,\"tick_age_unavailable_reason\":\"Broker UTC offset and clock synchronisation are unverified\"}";
}
bool props_ok=true;
long PI(ENUM_POSITION_PROPERTY_INTEGER p){long v=0;if(!PositionGetInteger(p,v))props_ok=false;return v;}
double PD(ENUM_POSITION_PROPERTY_DOUBLE p){double v=0;if(!PositionGetDouble(p,v)||!MathIsValidNumber(v))props_ok=false;return v;}
string PS(ENUM_POSITION_PROPERTY_STRING p){string v="";if(!PositionGetString(p,v))props_ok=false;return v;}
long OI(ENUM_ORDER_PROPERTY_INTEGER p){long v=0;if(!OrderGetInteger(p,v))props_ok=false;return v;}
double OD(ENUM_ORDER_PROPERTY_DOUBLE p){double v=0;if(!OrderGetDouble(p,v)||!MathIsValidNumber(v))props_ok=false;return v;}
string OS(ENUM_ORDER_PROPERTY_STRING p){string v="";if(!OrderGetString(p,v))props_ok=false;return v;}
string SortedList(string &items[]){for(int i=0;i<ArraySize(items);i++)for(int j=i+1;j<ArraySize(items);j++)if(StringCompare(items[i],items[j])>0){string t=items[i];items[i]=items[j];items[j]=t;}string s="";for(int i=0;i<ArraySize(items);i++)Append(s,items[i]);return "["+s+"]";}
string PositionsRead(string symbol,string &status){
 string items[];status="success";int count=PositionsTotal();
 for(int i=0;i<count;i++){
  ulong selected=PositionGetTicket(i);if(selected==0){status="partial";continue;}props_ok=true;string sym=PS(POSITION_SYMBOL);if(!props_ok){status="partial";continue;}if(sym!=symbol)continue;
  long id=PI(POSITION_IDENTIFIER),ticket=PI(POSITION_TICKET),type=PI(POSITION_TYPE),opened=PI(POSITION_TIME),updated=PI(POSITION_TIME_UPDATE);
  double open=PD(POSITION_PRICE_OPEN),volume=PD(POSITION_VOLUME),sl=PD(POSITION_SL),tp=PD(POSITION_TP);
  if(!props_ok||open<=0||volume<=0||sl<0||tp<0||(type!=POSITION_TYPE_BUY&&type!=POSITION_TYPE_SELL)){status="partial";continue;}
  string s="{\"position_id\":"+Q(I(id))+",\"position_ticket\":"+Q(I(ticket))+",\"symbol\":"+Q(sym)+",\"direction\":"+Q(type==POSITION_TYPE_BUY?"buy":"sell")+",\"open_price\":"+P(open)+",\"volume\":"+N(volume)+",\"volume_unit\":\"lots\",\"sl\":"+NullablePrice(sl)+",\"tp\":"+NullablePrice(tp)+",\"opened_at_server\":"+ST(opened)+",\"updated_at_server\":"+ST(updated)+"}";
  int n=ArraySize(items);ArrayResize(items,n+1);items[n]=s;
 }
 if(PositionsTotal()!=count)status="partial";return SortedList(items);
}
string OrdersRead(string symbol,string &status){
 string items[];status="success";int count=OrdersTotal();
 for(int i=0;i<count;i++){
  ulong selected=OrderGetTicket(i);if(selected==0){status="partial";continue;}props_ok=true;string sym=OS(ORDER_SYMBOL);if(!props_ok){status="partial";continue;}if(sym!=symbol)continue;
  long ticket=OI(ORDER_TICKET),type=OI(ORDER_TYPE),setup=OI(ORDER_TIME_SETUP),expiration=OI(ORDER_TIME_EXPIRATION),time_type=OI(ORDER_TYPE_TIME),state=OI(ORDER_STATE);
  double price=OD(ORDER_PRICE_OPEN),volume=OD(ORDER_VOLUME_CURRENT),sl=OD(ORDER_SL),tp=OD(ORDER_TP),stoplimit=OD(ORDER_PRICE_STOPLIMIT);
  if(!props_ok||price<=0||volume<=0||type<ORDER_TYPE_BUY_LIMIT||type>ORDER_TYPE_SELL_STOP_LIMIT){status="partial";continue;}
  string s="{\"order_ticket\":"+Q(I(ticket))+",\"symbol\":"+Q(sym)+",\"order_type\":"+Q(EnumToString((ENUM_ORDER_TYPE)type))+",\"order_state\":"+Q(EnumToString((ENUM_ORDER_STATE)state))+",\"requested_price\":"+P(price)+",\"stop_limit_price\":"+((type==ORDER_TYPE_BUY_STOP_LIMIT||type==ORDER_TYPE_SELL_STOP_LIMIT)?P(stoplimit):"null")+",\"volume_remaining\":"+N(volume)+",\"volume_unit\":\"lots\",\"sl\":"+NullablePrice(sl)+",\"tp\":"+NullablePrice(tp)+",\"time_type\":"+Q(EnumToString((ENUM_ORDER_TYPE_TIME)time_type))+",\"setup_at_server\":"+ST(setup)+",\"expiration_at_server\":"+ST(expiration)+"}";
  int n=ArraySize(items);ArrayResize(items,n+1);items[n]=s;
 }
 if(OrdersTotal()!=count)status="partial";return SortedList(items);
}
bool ValidBar(MqlRates &b){return b.time>0&&MathIsValidNumber(b.open)&&MathIsValidNumber(b.high)&&MathIsValidNumber(b.low)&&MathIsValidNumber(b.close)&&b.low>0&&b.low<=MathMin(b.open,b.close)&&MathMax(b.open,b.close)<=b.high;}
string Bar(MqlRates &b,bool closed){return "{\"time_open_server\":"+ST(b.time)+",\"open\":"+P(b.open)+",\"high\":"+P(b.high)+",\"low\":"+P(b.low)+",\"close\":"+P(b.close)+",\"is_closed\":"+B(closed)+",\"tick_volume\":"+I(b.tick_volume)+",\"spread_points_raw\":"+I(b.spread)+"}";}
struct Frame {
 ENUM_TIMEFRAMES tf;string name;int screen_count,history_count;long chart;int width,actual,partial,chart_scale,spacing,plot_bottom;double shift;
 datetime identity;MqlRates rates[];string read_start,read_end,capture_start,capture_end,capture_quote;ulong capture_duration;
};
bool ReadFrame(string symbol,Frame &f){
 f.read_start=UTC();int n=CopyRates(symbol,f.tf,0,f.history_count+1,f.rates);f.read_end=UTC();
 if(n!=f.history_count+1)return false;
 for(int i=0;i<n;i++)if(!ValidBar(f.rates[i])||(i>0&&f.rates[i].time<=f.rates[i-1].time))return false;
 return f.rates[n-1].time==f.identity;
}
string FrameJSON(Frame &f,int height,int tolerance){
 string bars="",gaps="",warn="";int n=f.history_count;
 for(int i=0;i<n;i++)Append(bars,Bar(f.rates[i],true));
 for(int i=1;i<=n;i++){long delta=f.rates[i].time-f.rates[i-1].time;if(delta!=PeriodSeconds(f.tf))Append(gaps,"{\"from_open_server\":"+ST(f.rates[i-1].time)+",\"to_open_server\":"+ST(f.rates[i].time)+",\"delta_seconds\":"+I(delta)+",\"cause\":null}");}
 if(f.actual!=f.screen_count)Append(warn,Issue("VISUAL_COUNT_MISMATCH",f.name,"Native full candle count differs within configured tolerance","visual_count"));
 return "{\"timeframe\":"+Q(f.name)+",\"chart_mode\":\"clean_native_candles\",\"layout\":{\"right_margin_percent\":"+N(f.shift)+",\"native_zoom\":"+I(f.chart_scale)+"},\"capture_annotations\":{\"quote_line\":\"frozen_capture_bid\",\"price_scale_label\":true,\"forming_marker\":true,\"forming_open_server\":"+ST(f.identity)+"},\"requested_screenshot_bars\":"+I(f.screen_count)+",\"actual_screenshot_bars\":"+I(f.actual)+",\"partial_screenshot_bars\":"+I(f.partial)+",\"screenshot_tolerance_bars\":"+I(tolerance)+",\"requested_closed_bars\":"+I(n)+",\"exported_closed_bars\":"+I(n)+",\"history_first_open_server\":"+ST(f.rates[0].time)+",\"history_last_closed_open_server\":"+ST(f.rates[n-1].time)+",\"data_read_started_at_utc\":"+Q(f.read_start)+",\"data_read_completed_at_utc\":"+Q(f.read_end)+",\"screenshot_file\":"+Q(f.name+".png")+",\"screenshot_requested_at_utc\":"+Q(f.capture_start)+",\"screenshot_saved_at_utc\":"+Q(f.capture_end)+",\"screenshot_duration_ms\":"+I((long)f.capture_duration)+",\"screenshot_width\":"+I(f.width)+",\"screenshot_height\":"+I(height)+",\"visible_first_open_server\":"+ST(f.rates[n-(f.actual-1)].time)+",\"visible_last_open_server\":"+ST(f.identity)+",\"screenshot_includes_forming\":true,\"capture_quote\":"+f.capture_quote+",\"closed_candles\":["+bars+"],\"forming_candle\":"+Bar(f.rates[n],false)+",\"forming_candle_status\":\"available\",\"forming_candle_read_started_at_utc\":"+Q(f.read_start)+",\"forming_candle_read_completed_at_utc\":"+Q(f.read_end)+",\"forming_values_may_differ\":true,\"indicators\":[],\"chart_objects\":[],\"history_status\":\"success\",\"time_gaps\":["+gaps+"],\"status\":"+Q(warn==""?"complete":"complete_with_warnings")+",\"warnings\":["+warn+"]}";
}
#endif
