codeunit 50103 "Loan Calculations Tests"
{
    Subtype = Test;

    var
        Assert: Codeunit "Library Assert";
        LoanCalc: Codeunit "Loan Calculations";

    [Test]
    procedure SimplePass_TEST()
    var
        ExpectedValue: Decimal;
        ActualValue: Decimal;
    begin
        ExpectedValue := 1;
        ActualValue := 1;
        Assert.AreEqual(ExpectedValue, ActualValue, 'This test should pass');
    end;

    [Test]
    procedure RawCalculation_TEST()
    var
        ExpectedMonthlyPayment: Decimal;
        ActualMonthlyPayment: Decimal;
    begin
        ExpectedMonthlyPayment := 2684.11; // Manually calculated outside of system
        ActualMonthlyPayment := LoanCalc.MonthlyPayment(500000, 5, 30 * 12);
        ActualMonthlyPayment := Round(ActualMonthlyPayment, 0.01);

        Assert.AreNearlyEqual(ExpectedMonthlyPayment, ActualMonthlyPayment, 0.001, 'Monthly payment calculation is incorrect');
    end;

    [Test]
    procedure UpdateLoanCalculation_TEST()
    var
        LoanMaster: Record "Loan Master";
        ExpectedMonthlyPayment: Decimal;
    begin
        LoanMaster.Init();
        LoanMaster."Loan ID" := 'TEST001';
        LoanMaster."Customer No." := 'CUST001';
        LoanMaster."Loan Amount" := 500000;
        LoanMaster."Interest Rate" := 5;
        LoanMaster."Loan Term" := 30 * 12;
        LoanMaster."Start Date" := DMY2Date(2, 1, 2023);
        LoanMaster.Insert();

        LoanCalc.UpdateLoanCalculation(LoanMaster);

        LoanMaster.Get('TEST001');
        ExpectedMonthlyPayment := 2684.11; // Manually calculated outside of system
        Assert.AreNearlyEqual(ExpectedMonthlyPayment, LoanMaster."Monthly Payment", 0.001, 'Monthly payment calculation is incorrect');
        Assert.AreEqual(DMY2Date(2, 1, 2053), LoanMaster."End Date", 'End date calculation is incorrect');
    end;
}