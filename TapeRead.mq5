//+------------------------------------------------------------------+
//|                                                     TapeRead.mq5 |
//|                        Copyright 2018, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+

#include "class\CommonConsts.mqh"
#include "class\Context.mqh"
#include "class\BookEngine.mqh"
#include "class\TVolumeTracker.mqh"
#include "class\PositionsControl.mqh"
#include "class\TPriceLines.mqh"
#include "class\TSignalGenerator.mqh"
#include "class\TDataLogger.mqh"
#include "class\TSignalStrategy.mqh"

//--- input parameters
input string   Aux_Contract="DOLQ21";

input long     DolVol_Threshold = 180; // Limite para Volume
input long     WdoVol_Threshold = 180; // Limite para Volume
input long     MaxHighSamples   = 5;
input int      SamplesNumber     =  20; // Num max de Amostras

string Contract;
bool tradeEnable = true;
Context *wdoCtx, *dolCtx;
TVolumeTracker *wdoTracker, *dolTracker;
PositionsControl expertPosition;
BookEngine engine;
TPriceLines dolLine,wdoLine;
TSignalGenerator* sigGen;
TArrowCol arrowCol;
TDataLogger* gDLog;
TSignalStrategy* gTss;


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit(){
  
   string msg;
   MqlDateTime t;
//--- create timer
   //EventSetTimer(60);
//---
   TimeTradeServer(t);
   if (t.hour < 17) EventSetTimer(600); //10Min
   else if (t.min < 50)  EventSetTimer(300); //5Min
   else {
      Print("Sifronio Sysytem is unable to init. Time is to close to trade session finish.");
      ExpertRemove();
   }
   bool EATradeAllowed=AccountInfoInteger(ACCOUNT_TRADE_EXPERT);
   bool RUNNING_REAL_ACCOUNT = 
      (ACCOUNT_TRADE_MODE_REAL==(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE));
   if (RUNNING_REAL_ACCOUNT){
      msg = StringFormat("Starting expert for %s on REAL account!\nDo you confirm?",Symbol());
      int ret = MessageBox(msg,"WARNNING! REAL ACCOUNT!",MB_ICONQUESTION|MB_YESNO);
      if (ret != IDYES) {
         Print("Sifronio System was NOT allowed on REAL account!");
         ExpertRemove();
      }
   }
   Contract = Symbol();
   PrintFormat("Starting EA on %s%s.",Contract,RUNNING_REAL_ACCOUNT?" on REAL account":"");
   //position.setMagic(MAGIC_NUMBER);        //tell position control our expert magic number to identify positions it opens
   
   if (!MarketBookAdd(Aux_Contract)) {       //Register expert to listen book events for Symbols
      msg = StringFormat("ERROR: MarketBookAdd fails for %s",Aux_Contract);
      MessageBox(msg,"SORRY!!!",MB_ICONERROR|MB_OK);
      ExpertRemove();
      return(INIT_FAILED);
   }
    if (!MarketBookAdd(Contract)) {
      msg = StringFormat("ERROR: MarketBookAdd fails for %s",Contract);
      MessageBox(msg,"SORRY!!!",MB_ICONERROR||MB_OK);
      ExpertRemove();
      return(INIT_FAILED);
   }
                                             //Create context and trackers
   wdoCtx = new Context(Contract,MaxHighSamples); wdoTracker = new TVolumeTracker(Contract,MaxHighSamples,WdoVol_Threshold);
   dolCtx = new Context(Aux_Contract,MaxHighSamples); dolTracker = new TVolumeTracker(Aux_Contract,MaxHighSamples,DolVol_Threshold);
   
   //Add Listeners to expert book listener engine
   
   engine.addListener(wdoCtx); engine.addListener(wdoTracker);
   engine.addListener(dolCtx); engine.addListener(dolTracker);
   
   //Create reference lines on graphic
   
   wdoLine.init(Contract,clrTurquoise);
   dolLine.init(Aux_Contract,clrPink);
   
   sigGen = new TSignalGenerator(wdoCtx);    //Create signal generator for Wdo MiniContracts
   gDLog = new TDataLogger();                //Create DataLgger
   gTss = new TSignalStrategy();
   gTss.connectCtx(wdoCtx,wdoTracker);
   gTss.connectLogger(gDLog);
   sigGen.connect(wdoTracker);               
   sigGen.connectLogger(gDLog);
   sigGen.addStrategy(gTss);
   Print("Cheking for open position.");
   expertPosition.loadPositions();
   Print("Done.");
   Print("Sifronio System initialized");
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("Sifronio System shutdown");
//--- destroy timer
   EventKillTimer();
   MarketBookRelease(Aux_Contract); MarketBookRelease(Contract);
   delete(gTss);
   delete sigGen;
   delete gDLog;
   delete dolCtx; delete dolTracker;
   delete wdoCtx; delete wdoTracker;
   switch(reason) {
      case REASON_INITFAILED:
         PrintFormat("[ERROR] Expert initialization for %s failed.",Contract);
         break;
      case REASON_RECOMPILE:
         PrintFormat("[INFO] Expert recompilation.");
      default:
         PrintFormat("EA removed.");
   }
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---
   MqlTick lastTick;
   string msg=""; bool isOn = false;
   if (!wdoTracker.processData()) return;
   
   if(SymbolInfoTick(Contract,lastTick))
   {
      Print("\n---");
      wdoTracker.calcGlobalMarketForce();
      wdoTracker.calcImediateForce(lastTick);
      wdoTracker.calcNewForce(lastTick);
      wdoTracker.classify(lastTick);
      isOn = sigGen.check(lastTick);
      if (wdoTracker.signalForce()) {
         
         PrintFormat("[%s] tick ASK(%6.1f) BID(%6.1f) vol(%6d)",TimeToString(lastTick.time,TIME_SECONDS),
                      lastTick.ask, lastTick.bid,lastTick.volume);
         wdoCtx.print();
         Print(sigGen.tradeSignal.toString());
      }
      
      if (isOn) {
         //if (!wdoTracker.signalForce()) Print(sigGen.tradeSignal.toString());
         if (tradeEnable) expertPosition.handleSignal(sigGen.tradeSignal, msg);
         switch(sigGen.tradeSignal.tip){
            case SIG_DRAW_BUY:
               arrowCol.addUpSL(lastTick.time,sigGen.tradeSignal.sl);
               arrowCol.addDown(lastTick.time,sigGen.tradeSignal.buyTP);
            break;
            case SIG_DRAW_SELL:
               arrowCol.addDownSL(lastTick.time,sigGen.tradeSignal.sl);
               arrowCol.addUp(lastTick.time,sigGen.tradeSignal.sellTP);
            break;
         }
         
      }
      expertPosition.checkTrailStop(75);
      /*   if (expertPosition.isReady()) 
         switch(sigGen.tradeSignal.tip) {
            case SIG_BUY:
               if (expertPosition.isBought()) {     //case SIG_SLTP:
                  if (expertPosition.getPositionTP() > sigGen.tradeSignal.tp || expertPosition.getStopLoss() >=sigGen.tradeSignal.sl){
                     msg = StringFormat("%s[SIG-CHK SL TP] BUY",msg);
                     sigGen.tradeSignal.tip = SIG_SLTP;
                  }  
               } else
                  if (sigGen.tradeSignal.tp - lastTick.ask > 2.5 && lastTick.ask - sigGen.tradeSignal.sl >=2) {
                     msg = StringFormat("%s[SIG-TRADE] BUY",msg);
                     expertPosition.checkBuy(lastTick.ask,1, sigGen.tradeSignal.sl,sigGen.tradeSignal.tp);
                  }
            break;
            case SIG_SELL:
               if (expertPosition.isSold())  {      //case SIG_SLTP:
                  if (expertPosition.getPositionTP() > sigGen.tradeSignal.tp || expertPosition.getStopLoss() > sigGen.tradeSignal.sl){
                     msg = StringFormat("%s[SIG-CHK SL TP] SELL",msg);
                     sigGen.tradeSignal.tip = SIG_SLTP;
                  }
               }else
                  if (lastTick.bid - sigGen.tradeSignal.tp > 2.5 && sigGen.tradeSignal.sl - lastTick.bid >= 2) {
                     msg = StringFormat("%s[SIG-TRADE] SELL",msg);
                     expertPosition.checkSell(lastTick.bid,1,sigGen.tradeSignal.sl,sigGen.tradeSignal.tp);
                  }
            break;
         }
         else
            PrintFormat("%s Position controler not ready: %s", LOG_ID, sigGen.toString());
         if (sigGen.tradeSignal.tip == SIG_SLTP)
            expertPosition.modify(sigGen.tradeSignal.sl,sigGen.tradeSignal.tp);

      }*/
      
      if (StringLen(msg) > 0) Print(msg);
      wdoTracker.print(lastTick);
      wdoTracker.clear();
      sigGen.clear();
      
      wdoLine.update(wdoCtx.getSellPrice(0),wdoCtx.getBuyPrice(0));
      dolLine.update(dolCtx.getSellPrice(0),dolCtx.getBuyPrice(0));
   }
  }
//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
   MqlDateTime t;
//---
   TimeTradeServer(t);
   if (t.hour < 17 || t.hour > 18) return;
   else if (t.min < 48)  return;
   else {
      Print("Sifronio Sysytem trade time limit reached. Trade is disabled.");
      tradeEnable = false;
      expertPosition.closeAll();
   }
  }
//+------------------------------------------------------------------+
//| Trade function                                                   |
//+------------------------------------------------------------------+
void OnTrade()
  {
//---
   PrintFormat("On trade Called %s",TimeToString(TimeCurrent(),TIME_SECONDS));
  }
//+------------------------------------------------------------------+
//| TradeTransaction function                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
  {
//---
   expertPosition.handleTradeTransaction(trans,request,result);
  }
//+------------------------------------------------------------------+
//| Tester function                                                  |
//+------------------------------------------------------------------+
double OnTester()
  {
//---
   double ret=0.0;
//---

//---
   return(ret);
  }
//+------------------------------------------------------------------+
//| TesterInit function                                              |
//+------------------------------------------------------------------+
void OnTesterInit()
  {
//---
   
  }
//+------------------------------------------------------------------+
//| TesterPass function                                              |
//+------------------------------------------------------------------+
void OnTesterPass()
  {
//---
   
  }
//+------------------------------------------------------------------+
//| TesterDeinit function                                            |
//+------------------------------------------------------------------+
void OnTesterDeinit()
  {
//---
   
  }
//+------------------------------------------------------------------+
//| ChartEvent function                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
//---
     if(id==CHARTEVENT_KEYDOWN) 
      switch((int)lparam) {
         case 115: 
            Print("Sell Event"); expertPosition.externalSell();
         break;
         case 98: 
         Print("Buy Event"); expertPosition.externalBuy();
         break;
      }
   
  }
//+------------------------------------------------------------------+
//| BookEvent function                                               |
//+------------------------------------------------------------------+
void OnBookEvent(const string &lsymbol)
  {
//---
   engine.run(lsymbol);
  }
//+------------------------------------------------------------------+
