codeunit 50102 "Loan Calculations"
{
    procedure PeriodPayment(LoanAmount: Decimal; PeriodRate: Decimal; NumPeriods: Integer): Decimal
    var
        Payment: Decimal;
    begin
        // Simple validation - complex cases might have negative rate?
        if (NumPeriods <= 0) or (LoanAmount < 0) or (PeriodRate < 0) then
            exit(0);

        if (PeriodRate = 0) then
            exit(LoanAmount / NumPeriods);

        Payment := (LoanAmount * PeriodRate * Power(1 + PeriodRate, NumPeriods)) /
                (Power(1 + PeriodRate, NumPeriods) - 1);

        exit(Payment);
    end;

    procedure MonthlyPayment(LoanAmount: Decimal; AnnualRate: Decimal; NumMonths: Integer): Decimal
    var
        Payment: Decimal;
    begin
        exit(PeriodPayment(LoanAmount, AnnualRate / 1200, NumMonths));
    end;

    /// <summary>
    /// Given a Loan Master record, calculate and set the monthly payment and/or end date.
    /// </summary>
    /// <param name="LoanMaster">The Loan Master record to update.</param>
    procedure UpdateLoanCalculation(var LoanMaster: Record "Loan Master")
    var
        MonthlyInterestRate: Decimal;
        NumberOfPayments: Integer;
        CalculatedEndDate: Date;
        CalculatedPayment: Decimal;
    begin
        CalculatedEndDate := LoanMaster."End Date";
        if (LoanMaster."Loan Term" > 0) then
            CalculatedEndDate := CalcDate('<' + Format(LoanMaster."Loan Term") + 'M>', LoanMaster."Start Date");

        CalculatedPayment := PeriodPayment(LoanMaster."Loan Amount", LoanMaster."Interest Rate" / 1200, LoanMaster."Loan Term");
        CalculatedPayment := Round(CalculatedPayment, 0.01);

        if (LoanMaster."End Date" <> CalculatedendDate) or (LoanMaster."Monthly Payment" <> CalculatedPayment) then begin
            LoanMaster."End Date" := CalculatedEndDate;
            LoanMaster."Monthly Payment" := CalculatedPayment;
            LoanMaster.Modify(true);
        end;
    end;
}
