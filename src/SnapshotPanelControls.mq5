#property strict
#property version "1.02"
#property indicator_chart_window
#property indicator_plots 1
#property indicator_buffers 1
#property indicator_type1 DRAW_NONE
double control_buffer[];
input long PanelChart=0;
input ulong InstanceEpoch=0; // Separate event state for each script launch.
long panel_chart=0;string panel_prefix="";
bool saved_scroll=true,scroll_captured=false;
bool old_mouse=false,dragging=false,previous_down=false,collapsed=false,hidden=false,ready=false;
int start_x=0,start_y=0,origin_x=0,origin_y=0,panel_width=0,panel_height=0;
ulong last_move=0;
ulong header_pressed_at=0,last_header_click=0;
int header_click_x=0,header_click_y=0;
bool header_moved=false;
string controls[];int rel_x[],rel_y[];
string Id(string s){return panel_prefix+s;}
string ViewFile(){return "MTSE\\panel_"+IntegerToString(panel_chart)+".txt";}
bool HeaderControl(string name){return name==Id("bg")||name==Id("title")||name==Id("min")||name==Id("close");}
void SaveView(){
 if(ObjectFind(panel_chart,Id("bg"))<0)return;
 int f=FileOpen(ViewFile(),FILE_WRITE|FILE_TXT|FILE_ANSI);
 if(f==INVALID_HANDLE)return;
 FileWriteString(f,IntegerToString((int)ObjectGetInteger(panel_chart,Id("bg"),OBJPROP_XDISTANCE))+" "+
 IntegerToString((int)ObjectGetInteger(panel_chart,Id("bg"),OBJPROP_YDISTANCE))+" "+
 IntegerToString(collapsed?1:0)+" "+IntegerToString(hidden?1:0));
 FileClose(f);
}
void Visibility(){
 for(int i=0;i<ArraySize(controls);i++){
 string n=controls[i];bool show=n==Id("open")?hidden:(!hidden&&(!collapsed||HeaderControl(n)));
 ObjectSetInteger(panel_chart,n,OBJPROP_TIMEFRAMES,show?OBJ_ALL_PERIODS:OBJ_NO_PERIODS);
 }
 double factor=MathMax(1.0,(double)TerminalInfoInteger(TERMINAL_SCREEN_DPI)/96.0);
 ObjectSetInteger(panel_chart,Id("bg"),OBJPROP_YSIZE,collapsed?(int)(44*factor):panel_height);
 ObjectSetString(panel_chart,Id("min"),OBJPROP_TEXT,collapsed?"+":"-");
 ChartRedraw(panel_chart);SaveView();
}
void Move(int x,int y,bool force=false){
 ulong now=GetTickCount64();if(!force&&now-last_move<25)return;
 int w=(int)ChartGetInteger(panel_chart,CHART_WIDTH_IN_PIXELS),h=(int)ChartGetInteger(panel_chart,CHART_HEIGHT_IN_PIXELS);
 int nx=MathMax(0,MathMin(w-panel_width,x)),ny=MathMax(0,MathMin(h-(collapsed?88:panel_height),y));
 for(int i=0;i<ArraySize(controls);i++)if(controls[i]!=Id("open")){
 ObjectSetInteger(panel_chart,controls[i],OBJPROP_XDISTANCE,nx+rel_x[i]);
 ObjectSetInteger(panel_chart,controls[i],OBJPROP_YDISTANCE,ny+rel_y[i]);
 }
 last_move=now;ChartRedraw(panel_chart);
}
void InitControls(){
 if(ObjectFind(panel_chart,Id("bg"))<0)return;
 int bx=(int)ObjectGetInteger(panel_chart,Id("bg"),OBJPROP_XDISTANCE),by=(int)ObjectGetInteger(panel_chart,Id("bg"),OBJPROP_YDISTANCE);
 panel_width=(int)ObjectGetInteger(panel_chart,Id("bg"),OBJPROP_XSIZE);panel_height=(int)ObjectGetInteger(panel_chart,Id("bg"),OBJPROP_YSIZE);
 for(int i=0;i<ObjectsTotal(panel_chart);i++){
 string n=ObjectName(panel_chart,i);if(StringFind(n,panel_prefix)!=0)continue;
 int j=ArraySize(controls);ArrayResize(controls,j+1);ArrayResize(rel_x,j+1);ArrayResize(rel_y,j+1);
 controls[j]=n;rel_x[j]=(int)ObjectGetInteger(panel_chart,n,OBJPROP_XDISTANCE)-bx;rel_y[j]=(int)ObjectGetInteger(panel_chart,n,OBJPROP_YDISTANCE)-by;
 }
 ready=true;int f=FileOpen(ViewFile(),FILE_READ|FILE_TXT|FILE_ANSI);
 ObjectSetString(panel_chart,Id("title"),OBJPROP_TOOLTIP,"Double-click to collapse / expand. Drag to move.");
 if(f!=INVALID_HANDLE){string vals[];StringSplit(FileReadString(f),' ',vals);FileClose(f);
 if(ArraySize(vals)==4){collapsed=StringToInteger(vals[2])!=0;hidden=StringToInteger(vals[3])!=0;Move((int)StringToInteger(vals[0]),(int)StringToInteger(vals[1]),true);}
 }
 Visibility();
}
int OnInit(){
 SetIndexBuffer(0,control_buffer,INDICATOR_DATA);PlotIndexSetInteger(0,PLOT_SHOW_DATA,false);
 int debug=FileOpen("MTSE\\panel_init.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);if(debug!=INVALID_HANDLE){FileWriteString(debug,_Symbol+"/"+IntegerToString(_Period)+" chart="+IntegerToString(ChartID()));FileClose(debug);}

 panel_chart=PanelChart==0?ChartID():PanelChart;panel_prefix="MTSE_"+IntegerToString(panel_chart)+"_";
 IndicatorSetString(INDICATOR_SHORTNAME,"Snapshot panel controls");
 old_mouse=(bool)ChartGetInteger(panel_chart,CHART_EVENT_MOUSE_MOVE);
 ChartSetInteger(panel_chart,CHART_EVENT_MOUSE_MOVE,true);EventSetMillisecondTimer(100);
 return INIT_SUCCEEDED;
}
void OnTimer(){if(!ready)InitControls();}
void OnDeinit(const int reason){
 EventKillTimer();if(ready)SaveView();
 if(scroll_captured)ChartSetInteger(panel_chart,CHART_MOUSE_SCROLL,saved_scroll);
 // Levels and Zones may share mouse events. Do not disable another panel's listener.
 if(!old_mouse&&ObjectFind(panel_chart,"LZ_INSTANCE")<0)ChartSetInteger(panel_chart,CHART_EVENT_MOUSE_MOVE,false);
}
void OnChartEvent(const int id,const long &lp,const double &dp,const string &sp){
 if(!ready)return;
 if(id==CHARTEVENT_OBJECT_CLICK&&StringFind(sp,panel_prefix)==0){
 if(sp==Id("export")||sp==Id("close")||sp==Id("min")||sp==Id("open")){
 last_header_click=0;
 ObjectSetInteger(panel_chart,sp,OBJPROP_STATE,false);ChartRedraw(panel_chart);
 if(sp==Id("export")){if(GlobalVariableGet(Id("busy"))==0)GlobalVariableSet(Id("request"),1);}
 else if(sp==Id("close")){hidden=true;Visibility();}
 else if(sp==Id("open")){hidden=false;Visibility();}
 else {collapsed=!collapsed;Visibility();}
 }
 return;
 }
 if(id==CHARTEVENT_OBJECT_ENDEDIT&&StringFind(sp,panel_prefix)==0){GlobalVariableSet(Id("save"),1);return;}
 if(id==CHARTEVENT_MOUSE_MOVE){
 int x=(int)lp,y=(int)dp;bool down=((uint)StringToInteger(sp)&1)!=0;
 int tolerance=(int)(4*MathMax(1.0,(double)TerminalInfoInteger(TERMINAL_SCREEN_DPI)/96.0));
 if(dragging){
 if(MathAbs(x-start_x)>tolerance||MathAbs(y-start_y)>tolerance){header_moved=true;last_header_click=0;}
 Move(origin_x+x-start_x,origin_y+y-start_y,!down);
 if(!down){
 dragging=false;ulong now=GetTickCount64();
 if(!header_moved&&now-header_pressed_at<=500){
 if(last_header_click!=0&&now-last_header_click<=450&&MathAbs(x-header_click_x)<=tolerance&&MathAbs(y-header_click_y)<=tolerance){
 collapsed=!collapsed;last_header_click=0;Visibility();
 }else{last_header_click=now;header_click_x=x;header_click_y=y;}
 }else last_header_click=0;
 SaveView();if(scroll_captured){ChartSetInteger(panel_chart,CHART_MOUSE_SCROLL,saved_scroll);scroll_captured=false;}
 }
 }else if(down&&!previous_down&&!hidden){
 int bx=(int)ObjectGetInteger(panel_chart,Id("bg"),OBJPROP_XDISTANCE),by=(int)ObjectGetInteger(panel_chart,Id("bg"),OBJPROP_YDISTANCE);
 double factor=MathMax(1.0,(double)TerminalInfoInteger(TERMINAL_SCREEN_DPI)/96.0);
 if(x>=bx&&x<bx+panel_width-(int)(90*factor)&&y>=by&&y<by+(int)(42*factor)){
 saved_scroll=(bool)ChartGetInteger(panel_chart,CHART_MOUSE_SCROLL);scroll_captured=true;ChartSetInteger(panel_chart,CHART_MOUSE_SCROLL,false);
 dragging=true;start_x=x;start_y=y;origin_x=bx;origin_y=by;last_move=0;
 header_pressed_at=GetTickCount64();header_moved=false;
 }else last_header_click=0;
 }
 previous_down=down;
 }
}
int OnCalculate(const int n,const int prev,const datetime &t[],const double &o[],const double &h[],const double &l[],const double &c[],const long &tv[],const long &v[],const int &s[]){return n;}
