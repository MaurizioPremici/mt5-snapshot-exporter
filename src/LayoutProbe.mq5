#property strict
void OnStart(){
 long c=ChartOpen(_Symbol,PERIOD_H4); if(c==0)return;
 Sleep(2000); ChartSetInteger(c,CHART_SHOW_ONE_CLICK,false); ChartSetInteger(c,CHART_SHOW_TRADE_LEVELS,false);
 ChartSetInteger(c,CHART_AUTOSCROLL,true); ChartSetInteger(c,CHART_SHIFT,false);
 int f=FileOpen("MTSE_probe.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
 for(int s=0;s<6;s++){
 ChartSetInteger(c,CHART_SCALE,s);ChartNavigate(c,CHART_END,0);ChartRedraw(c);Sleep(300);
 int x,y,x1,y1; double p=iClose(_Symbol,PERIOD_H4,0);
 ChartTimePriceToXY(c,0,iTime(_Symbol,PERIOD_H4,0),p,x,y);ChartTimePriceToXY(c,0,iTime(_Symbol,PERIOD_H4,1),p,x1,y1);
 FileWrite(f,StringFormat("scale=%d width=%d height=%d visible=%d first=%d x0=%d x1=%d step=%d",s,(int)ChartGetInteger(c,CHART_WIDTH_IN_PIXELS),(int)ChartGetInteger(c,CHART_HEIGHT_IN_PIXELS),(int)ChartGetInteger(c,CHART_VISIBLE_BARS),(int)ChartGetInteger(c,CHART_FIRST_VISIBLE_BAR),x,x1,x-x1));
 if(s==3) {ChartScreenShot(c,"MTSE_probe.png",2400,1400,ALIGN_RIGHT);Sleep(700);}
 }
 FileClose(f); ChartClose(c);
}
