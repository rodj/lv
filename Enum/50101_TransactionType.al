enum 50100 "Loan Transaction Type"
{
    Extensible = true;

    value(0; Disbursement)
    {
        Caption = 'Disbursement';
    }
    value(1; Repayment)
    {
        Caption = 'Repayment';
    }
    value(2; Test)
    {
        Caption = 'Test';
    }
}