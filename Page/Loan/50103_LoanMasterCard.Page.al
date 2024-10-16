page 50103 "Loan Master Card"
{
    PageType = Card;
    SourceTable = "Loan Master";
    Caption = 'Loan Master';
    UsageCategory = Documents;
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            group(General)
            {
                field("Loan ID"; Rec."Loan ID")
                {
                    ApplicationArea = All;
                }
                field("Customer No."; Rec."Customer No.")
                {
                    ApplicationArea = All;
                }
                field("Loan Amount"; Rec."Loan Amount")
                {
                    ApplicationArea = All;
                    trigger OnValidate()
                    begin
                        UpdateLoanCalculations();
                    end;
                }
                field("Interest Rate"; Rec."Interest Rate")
                {
                    ApplicationArea = All;
                    trigger OnValidate()
                    begin
                        UpdateLoanCalculations();
                    end;
                }
                field("Loan Term"; Rec."Loan Term")
                {
                    ApplicationArea = All;
                    trigger OnValidate()
                    begin
                        UpdateLoanCalculations();
                    end;
                }
                field("Start Date"; Rec."Start Date")
                {
                    ApplicationArea = All;
                    trigger OnValidate()
                    begin
                        UpdateEndDate();
                    end;
                }
                field("End Date"; Rec."End Date")
                {
                    ApplicationArea = All;
                    Editable = false;
                }
                field("Monthly Payment"; Rec."Monthly Payment")
                {
                    ApplicationArea = All;
                    Editable = false;
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(PostPayment)
            {
                ApplicationArea = All;
                Caption = 'Post Payment';
                Image = Payment;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;

                trigger OnAction()
                var
                    Loan: Codeunit "Loan Journal Posting";
                    LoanCalc: Codeunit "Loan Calculations";
                    LoanJournalPosting: Codeunit "Loan Journal Posting";
                    PaymentInputPage: Page "PaymentInputPage";
                    UserInputPaymentAmount: Decimal;
                    ErrorText: Text;
                    PrepareOnly: Boolean;
                    Result: Boolean;
                    TransActionType: Enum "Loan Transaction Type";
                    Util: Codeunit "Utility";
                    S: Text;
                begin
                    if Rec."Monthly Payment" <= 0 then
                        LoanCalc.UpdateLoanCalculation(Rec);

                    PaymentInputPage.SetNumberInputField(Rec."Monthly Payment");

                    if PaymentInputPage.RunModal() = Action::OK then begin
                        UserInputPaymentAmount := PaymentInputPage.GetNumberInputField();

                        if UserInputPaymentAmount <= 0 then
                            Error('Payment amount must be greater than zero.');

                        // Ensure record is saved before posting
                        if Rec.Modify(true) then;
                        Commit();

                        PrepareOnly := true;
                        TransActionType := "Loan Transaction Type"::Repayment;
                        // procedure ProcessLoanTransaction(var LoanMaster: Record "Loan Master"; TransactionAmount: Decimal; PostingDate: Date; TransactionType: Option Disbursement,Repayment; PrepareOnly: Boolean): Boolean
                        Result := Loan.ProcessLoanTransaction(Rec, UserInputPaymentAmount, WorkDate, TransactionType, PrepareOnly);

                        if Result then
                            Message('Journal entries have been prepared (but not posted) for loan repayment of %1', UserInputPaymentAmount)
                        else begin
                            ErrorText := GetLastErrorText();
                            if ErrorText = '' then
                                ErrorText := 'Unknown error occurred during loan disbursement posting.';
                            Error('Failed to post loan disbursement. Error: %1', ErrorText);
                        end;
                    end;
                end;
            }

            action(DisburseLoan)
            {
                ApplicationArea = All;
                Caption = 'Disburse Loan';
                Image = Item;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;

                trigger OnAction()
                var
                    Loan: Codeunit "Loan Journal Posting";
                    PrepareOnly: Boolean;
                    ErrorText: Text;
                    Result: Boolean;
                    TransActionType: Enum "Loan Transaction Type";
                    Util: Codeunit "Utility";
                    S: Text;
                begin
                    if Rec.ValidateLoanMasterRecord() then begin

                        ClearLastError();

                        PrepareOnly := false;
                        TransActionType := "Loan Transaction Type"::Disbursement;
                        // procedure ProcessLoanTransaction(var LoanMaster: Record "Loan Master"; TransactionAmount: Decimal; PostingDate: Date; TransactionType: Option Disbursement,Repayment; PrepareOnly: Boolean): Boolean
                        Result := Loan.ProcessLoanTransaction(Rec, Rec."Loan Amount", WorkDate, TransactionType, PrepareOnly);

                        if Result then
                            Message('Journal entries have been prepared (but not posted) for loan disbursement of %1', Rec."Loan Amount")
                        else begin
                            ErrorText := GetLastErrorText();
                            if ErrorText = '' then
                                ErrorText := 'Unknown error occurred during loan disbursement posting.';
                            Error('Failed to post loan disbursement. Error: %1', ErrorText);
                        end;
                    end else begin
                        Message('Unable to disburse');
                    end;
                end;
            }
        }
    }

    trigger OnNewRecord(BelowxRec: Boolean)
    begin
        CurrPage.Update(false)
    end;

    local procedure UpdateLoanCalculations()
    var
        LoanCalc: Codeunit "Loan Calculations";
        CalculatedPayment: Decimal;
    begin
        UpdateEndDate();

        CalculatedPayment := LoanCalc.MonthlyPayment(Rec."Loan Amount", Rec."Interest Rate", Rec."Loan Term");
        CalculatedPayment := Round(CalculatedPayment, 0.01);

        if Rec."Monthly Payment" <> CalculatedPayment then begin
            Rec."Monthly Payment" := CalculatedPayment;
            Rec.Modify(true);
        end;
    end;

    local procedure UpdateEndDate()
    begin
        if (Rec."Start Date" <> 0D) and (Rec."Loan Term" > 0) then begin
            Rec."End Date" := CalcDate('<' + Format(Rec."Loan Term") + 'M>', Rec."Start Date");
            Rec.Modify(true);
        end;
    end;
}