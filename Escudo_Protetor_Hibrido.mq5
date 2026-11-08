//+------------------------------------------------------------------+
//|                                    Escudo_Protetor_Hibrido.mq5   |
//|                                  Copyright 2026, Jocelio Silva   |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Jocelio Silva"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//--- Grupos de Parâmetros de Entrada (Inputs)
input group "=== GESTÃO DE RISCO E LOTES ==="
input double   InpLotInitial     = 0.01;      // Lote Inicial
input double   InpLotMultiplier  = 1.5;       // Multiplicador do Grid (Martingale suave)
input int      InpMaxTrades      = 7;         // Máximo de Ordens no Grid
input double   InpTakeProfitPips = 200;       // Take Profit Geral (pontos)
input double   InpStopLossPips   = 500;       // Stop Loss Geral (pontos)

input group "=== CONFIGURAÇÃO DO GRID COM DEFESA ==="
input double   InpGridStep       = 150;       // Distância entre ordens do Grid (pontos)
input bool     InpUseGridDefense = true;      // Ativar Defesa de Grid por Volatilidade
input int      InpATRPeriod      = 14;        // Período do ATR
input double   InpATRMultiplier  = 2.0;       // Multiplicador do Canal ATR

input group "=== BREAKEVEN E TRAILING STOP ==="
input bool     InpUseBreakeven   = true;      // Ativar Breakeven
input double   InpBETrigger      = 100;       // Gatilho Breakeven (pontos)
input double   InpBEBuffer       = 20;        // Lucro Garantido Breakeven (pontos)
input bool     InpUseTrailing    = true;      // Ativar Trailing Stop Dinâmico
input double   InpTrailingStop   = 80;        // Distância Trailing Stop (pontos)
input double   InpTrailingStep   = 20;        // Passo do Trailing Stop (pontos)

input group "=== CONFIGURAÇÃO VISUAL DO PAINEL ==="
input color    InpPanelBG        = clrDarkSlateGray; // Cor de Fundo do Painel
input color    InpTextColor      = clrWhite;         // Cor do Texto
input color    InpAccentColor    = clrGold;          // Cor de Destaque

//--- Variáveis Globais
datetime       g_last_bar_time   = 0;
int            g_atr_handle      = INVALID_HANDLE;
long           g_magic_number    = 20261101;
// Dimensões fixas do painel mantidas conforme referência padrão
const int      PANEL_WIDTH       = 320;
const int      PANEL_HEIGHT      = 220; 

// Declaração antecipada de funções
void CriaPainelControle();
void CriaRotuloTexto(string name, string text, int x, int y, int fontSize, color col);
void OnTick();
void ControlaGridDefesa();
int ContaOrdensAbertas();
double RetornaPrecoUltimaOrdem(ENUM_POSITION_TYPE pos_type);
void GerenciaSaidasInteligentes();
void AtualizaPainelDinamico();

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(g_magic_number);
   trade.SetDeviationInPoints(10);

   // Inicializa o indicador ATR para o canal de volatilidade
   g_atr_handle = iATR(_Symbol, _Period, InpATRPeriod);
   if(g_atr_handle == INVALID_HANDLE)
   {
      Print("Erro ao criar o handle do indicador ATR.");
      return(INIT_FAILED);
   }

   // Criação dos elementos visuais do painel no gráfico
   CriaPainelControle();

   Print("Escudo Protetor Híbrido inicializado com sucesso.");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Remove todos os objetos gráficos criados pelo EA no gráfico
   ObjectsDeleteAll(0, "EscudoPanel_");
   
   if(g_atr_handle != INVALID_HANDLE)
      IndicatorRelease(g_atr_handle);

   Print("Escudo Protetor Híbrido finalizado.");
}

//+------------------------------------------------------------------+
//| Função para criar o Painel Visual na Tela                        |
//+------------------------------------------------------------------+
void CriaPainelControle()
{
   string prefix = "EscudoPanel_";
   
   // Fundo do Painel (Mantendo largura e altura fixas padronizadas)
   ObjectCreate(0, prefix + "BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_YDISTANCE, 30);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_SIZE_X, PANEL_WIDTH);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_SIZE_Y, PANEL_HEIGHT);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_BGCOLOR, InpPanelBG);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_BORDER_COLOR, InpAccentColor);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);

   // Título do Painel
   ObjectCreate(0, prefix + "Title", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, prefix + "Title", OBJPROP_XDISTANCE, 35);
   ObjectSetInteger(0, prefix + "Title", OBJPROP_YDISTANCE, 45);
   ObjectSetString(0, prefix + "Title", OBJPROP_TEXT, "ESCUDO PROTETOR HÍBRIDO");
   ObjectSetString(0, prefix + "Title", OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, prefix + "Title", OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, prefix + "Title", OBJPROP_COLOR, InpAccentColor);

   // Rótulos de Status (Lucro, Posições e Defesa)
   CriaRotuloTexto(prefix + "LblStatus", "Status do Robô: ATIVO", 35, 75, 9, InpTextColor);
   CriaRotuloTexto(prefix + "LblSpread", "Spread Atual: --", 35, 100, 9, InpTextColor);
   CriaRotuloTexto(prefix + "LblGrid",   "Ordens em Grid: 0 / " + IntegerToString(InpMaxTrades), 35, 125, 9, InpTextColor);
   CriaRotuloTexto(prefix + "LblProfit", "Lucro Aberto: R$ 0.00", 35, 150, 10, InpAccentColor);
}

// Função auxiliar para criar rótulos de texto padronizados
void CriaRotuloTexto(string name, string text, int x, int y, int fontSize, color col)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Atualiza os dados do painel em tempo real
   AtualizaPainelDinamico();

   // Gerencia Breakeven e Trailing Stop para posições abertas
   if(InpUseBreakeven || InpUseTrailing)
      GerenciaSaidasInteligentes();

   // Verifica se é uma nova barra para validações de tendência/volatilidade
   datetime current_bar_time = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   if(current_bar_time == g_last_bar_time) return;
   g_last_bar_time = current_bar_time;

   // Lógica de Grid e Abertura de Posições
   ControlaGridDefesa();
}

//+------------------------------------------------------------------+
//| Controle de Grid e Defesa Baseada em ATR                         |
//+------------------------------------------------------------------+
void ControlaGridDefesa()
{
   int total_positions = ContaOrdensAbertas();
   
   if(total_positions == 0)
   {
      // Abre a primeira posição baseada na tendência ou padrão inicial (Compra por exemplo)
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = ask - (InpStopLossPips * _Point);
      double tp = ask + (InpTakeProfitPips * _Point);
      
      trade.Buy(InpLotInitial, _Symbol, ask, sl, tp, "Escudo: Início Grid");
   }
   else if(total_positions < InpMaxTrades)
   {
      // Verifica o preço da última ordem aberta para espaçamento do Grid
      double last_price = RetornaPrecoUltimaOrdem(POSITION_TYPE_BUY);
      double current_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      
      double atr_values[];
      ArraySetAsSeries(atr_values, true);
      if(CopyBuffer(g_atr_handle, 0, 0, 1, atr_values) > 0)
      {
         double dynamic_step = InpGridStep * _Point;
         if(InpUseGridDefense)
         {
            // Ajusta o passo do grid dinamicamente conforme a volatilidade do ATR
            dynamic_step = MathMax(InpGridStep * _Point, atr_values[0] * InpATRMultiplier);
         }

         // Se o preço cair além do passo ajustado, abre nova ordem de defesa do grid (Martingale)
         if(last_price - current_bid >= dynamic_step)
         {
            double next_lot = InpLotInitial * MathPow(InpLotMultiplier, total_positions);
            double sl = current_bid - (InpStopLossPips * _Point);
            double tp = current_bid + (InpTakeProfitPips * _Point);
            
            trade.Buy(next_lot, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK), sl, tp, "Escudo: Defesa Grid");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Conta quantas ordens abertas o EA possui                         |
//+------------------------------------------------------------------+
int ContaOrdensAbertas()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == g_magic_number)
      {
         count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Retorna o preço da última ordem aberta                           |
//+------------------------------------------------------------------+
double RetornaPrecoUltimaOrdem(ENUM_POSITION_TYPE pos_type)
{
   double lowest_price = 999999.0;
   double highest_price = 0.0;
   bool found = false;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == g_magic_number)
      {
         if(PositionGetInteger(POSITION_TYPE) == pos_type)
         {
            double price = PositionGetDouble(POSITION_PRICE_OPEN);
            if(pos_type == POSITION_TYPE_BUY)
            {
               if(!found || price < lowest_price) { lowest_price = price; found = true; }
            }
         }
      }
   }
   return (pos_type == POSITION_TYPE_BUY) ? lowest_price : highest_price;
}

//+------------------------------------------------------------------+
//| Gerencia Breakeven e Trailing Stop                               |
//+------------------------------------------------------------------+
void GerenciaSaidasInteligentes()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == g_magic_number)
      {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double current_sl = PositionGetDouble(POSITION_SL);
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         
         // Lógica de Breakeven
         if(InpUseBreakeven && current_sl < open_price)
         {
            if(bid - open_price >= InpBETrigger * _Point)
            {
               double new_sl = open_price + (InpBEBuffer * _Point);
               trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Atualiza as informações dinâmicas do painel                      |
//+------------------------------------------------------------------+
void AtualizaPainelDinamico()
{
   string prefix = "EscudoPanel_";
   
   // Calcula o lucro total aberto
   double total_profit = 0.0;
   int open_count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == g_magic_number)
      {
         total_profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP) + PositionGetDouble(POSITION_COMMISSION);
         open_count++;
      }
   }

   // Atualiza os textos dos rótulos no painel
   ObjectSetString(0, prefix + "LblGrid", OBJPROP_TEXT, "Ordens em Grid: " + IntegerToString(open_count) + " / " + IntegerToString(InpMaxTrades));
   ObjectSetString(0, prefix + "LblProfit", OBJPROP_TEXT, "Lucro Aberto: R$ " + DoubleToString(total_profit, 2));
   
   // Altera a cor do lucro dependendo se está positivo ou negativo
   color profit_color = (total_profit >= 0) ? clrLimeGreen : clrRed;
   ObjectSetInteger(0, prefix + "LblProfit", OBJPROP_COLOR, profit_color);
}