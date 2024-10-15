enum 50100 "Amount Filter Option"
{
    Extensible = true;

    value(0; All_Amounts) { Caption = 'All Amounts'; }
    value(1; To100k) { Caption = 'Up to 100k'; }
    value(2; Amt100kToMil) { Caption = '100k to 1 million'; }
    value(3; Over1Mil) { Caption = 'Over 1 million'; }
}