codeunit 50104 "Loan Journal Posting"
{
    var
        Util: Codeunit "Utility";

    // Wrapper function to maintain backward compatibility
    procedure PostLoanRepayment(LoanMaster: Record "Loan Master"; RepaymentAmount: Decimal; PostingDate: Date): Boolean
    begin
        exit(ProcessLoanTransaction(LoanMaster, RepaymentAmount, PostingDate, "Loan Transaction Type"::Repayment, false));
    end;

    // Wrapper function to maintain backward compatibility
    procedure LoanDisbursementHandleEntries(PrepareOnly: Boolean; LoanMaster: Record "Loan Master"; DisbursementAmount: Decimal; PostingDate: Date): Boolean
    begin
        exit(ProcessLoanTransaction(LoanMaster, DisbursementAmount, PostingDate, "Loan Transaction Type"::Disbursement, PrepareOnly));
    end;

    procedure ProcessLoanTransaction(var LoanMaster: Record "Loan Master"; TransactionAmount: Decimal; PostingDate: Date; TransactionType: enum "Loan Transaction Type"; PrepareOnly: Boolean): Boolean
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        GLSetup: Record "General Ledger Setup";
    begin
        if not LoanMaster.ValidateLoanMasterRecord() then
            exit(false);

        Util.GL_Setup();

        // Check G/L Setup for allowed posting dates
        GLSetup.Get();
        if (PostingDate < GLSetup."Allow Posting From") or (PostingDate > GLSetup."Allow Posting To") then begin
            Message('Posting date %1 is outside the allowed posting range (%2 to %3)',
                PostingDate, GLSetup."Allow Posting From", GLSetup."Allow Posting To");
            exit(false);
        end;

        // Find the default journal batch
        if not FindDefaultJournalBatch(GenJournalBatch) then begin
            Message('No default journal batch found');
            exit(false);
        end;

        // Process entries based on transaction type
        case TransactionType of
            "Loan Transaction Type"::Disbursement:
                begin
                    if not ProcessEntry(LoanMaster, TransactionAmount, false, PostingDate, PrepareOnly, GenJournalBatch) then
                        exit(false);
                    if not ProcessEntry(LoanMaster, -TransactionAmount, true, PostingDate, PrepareOnly, GenJournalBatch) then
                        exit(false);
                end;
            "Loan Transaction Type"::Repayment:
                begin
                    if not ProcessEntry(LoanMaster, TransactionAmount, true, PostingDate, PrepareOnly, GenJournalBatch) then
                        exit(false);
                    if not ProcessEntry(LoanMaster, -TransactionAmount, false, PostingDate, PrepareOnly, GenJournalBatch) then
                        exit(false);
                end;
        end;

        exit(true);
    end;

    local procedure ProcessEntry(var LoanMaster: Record "Loan Master"; Amount: Decimal; IsBankEntry: Boolean; PostingDate: Date; PrepareOnly: Boolean; var GenJournalBatch: Record "Gen. Journal Batch"): Boolean
    var
        GenJournalLine: Record "Gen. Journal Line";
        GenJnlPostLine: Codeunit "Gen. Jnl.-Post Line";
        ErrorText: Text;
    begin
        // Initialize journal line
        InitializeGenJournalLine(GenJournalLine, GenJournalBatch, LoanMaster, Amount, IsBankEntry, PostingDate);

        if PrepareOnly then
            GenJnlPostLine.RunWithCheck(GenJournalLine)
        else begin
            if not GenJnlPostLine.Run(GenJournalLine) then begin
                ErrorText := StrSubstNo('Failed to post journal line with Document No. %1 on Posting Date %2', GenJournalLine."Document No.", PostingDate);
                Message(ErrorText);
                exit(false);
            end;
        end;

        exit(true);
    end;

    local procedure InitializeGenJournalLine(var GenJournalLine: Record "Gen. Journal Line"; GenJournalBatch: Record "Gen. Journal Batch"; LoanMaster: Record "Loan Master"; Amount: Decimal; IsBankEntry: Boolean; PostingDate: Date)
    begin
        GenJournalLine.Init();
        GenJournalLine.Validate("Journal Template Name", GenJournalBatch."Journal Template Name");
        GenJournalLine.Validate("Journal Batch Name", GenJournalBatch.Name);
        GenJournalLine."Line No." := GetNextLineNo(GenJournalLine);
        GenJournalLine.Validate("Posting Date", PostingDate);
        GenJournalLine.Validate("Document No.", Util.LoanDocNo(LoanMaster."Loan ID"));
        GenJournalLine.Validate("Account Type", IsBankEntry ? GenJournalLine."Account Type"::"Bank Account" : GenJournalLine."Account Type"::"G/L Account");
        GenJournalLine.Validate("Account No.", IsBankEntry ? Util.CheckingAccountNo() : Util.LoanAccountNo());
        GenJournalLine.Validate(Amount, Amount);
        GenJournalLine.Validate(Description, StrSubstNo('Loan %1', Amount > 0 ? 'Disbursement' : 'Repayment'));
        GenJournalLine.Insert(true);
    end;

    local procedure GetNextLineNo(var GenJournalLine: Record "Gen. Journal Line"): Integer
    begin
        GenJournalLine.SetRange("Journal Template Name", GenJournalLine."Journal Template Name");
        GenJournalLine.SetRange("Journal Batch Name", GenJournalLine."Journal Batch Name");
        if GenJournalLine.FindLast() then
            exit(GenJournalLine."Line No." + 10000)
        else
            exit(10000);
    end;

    local procedure FindDefaultJournalBatch(var GenJournalBatch: Record "Gen. Journal Batch"): Boolean
    var
        GenJournalTemplate: Record "Gen. Journal Template";
    begin
        if not GenJournalTemplate.FindFirst() then
            exit(false);

        GenJournalBatch.SetRange("Journal Template Name", GenJournalTemplate.Name);
        GenJournalBatch.SetRange(Recurring, false);
        exit(GenJournalBatch.FindFirst());
    end;
}