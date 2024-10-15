codeunit 50104 "Loan Journal Posting"
{
    var
        Util: Codeunit "Utility";

    procedure PostLoanRepayment(LoanMaster: Record "Loan Master"; RepaymentAmount: Decimal; PostingDate: Date): Boolean
    var
        GenJournalLine: Record "Gen. Journal Line";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJnlPostLine: Codeunit "Gen. Jnl.-Post Line";
        GLSetup: Record "General Ledger Setup";
        PostingResult: Integer;
        ErrorText: Text;
        MyInfo: ErrorInfo;
    begin
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

        // Initialize and post bank account entry (Debit)
        InitializeGenJournalLine(GenJournalLine, GenJournalBatch, LoanMaster, RepaymentAmount, true, PostingDate);
        ClearLastError();
        PostingResult := GenJnlPostLine.RunWithCheck(GenJournalLine);
        if PostingResult <> 0 then begin
            ErrorText := GetLastErrorText();
            if ErrorText = '' then
                ErrorText := 'Unknown error occurred during bank account entry posting';
            Message('Failed to post bank account entry. Details: %1', ErrorText);
            exit(false);
        end;

        // Initialize and post loan receivable account entry (Credit)
        InitializeGenJournalLine(GenJournalLine, GenJournalBatch, LoanMaster, -RepaymentAmount, false, PostingDate);
        ClearLastError();
        PostingResult := GenJnlPostLine.RunWithCheck(GenJournalLine);
        exit(true);
    end;

    /// <summary>
    /// Prepare or Post journal entries for loan disbursement
    /// </summary>
    procedure LoanDisbursementHandleEntries(PrepareOnly: Boolean; LoanMaster: Record "Loan Master"; DisbursementAmount: Decimal; PostingDate: Date): Boolean
    var
        GenJournalLine: Record "Gen. Journal Line";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJnlPostLine: Codeunit "Gen. Jnl.-Post Line";
        GLSetup: Record "General Ledger Setup";
        ErrorText: Text;
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

        // Initialize and handle loan receivable account entry (Debit)
        InitializeGenJournalLine(GenJournalLine, GenJournalBatch, LoanMaster, DisbursementAmount, false, PostingDate);
        if PrepareOnly then
            GenJnlPostLine.RunWithCheck(GenJournalLine)  // Prepare: Validate and insert the journal line, but don't post
        else begin
            if not GenJnlPostLine.Run(GenJournalLine) then begin  // Post: Validate and post the journal line
                ErrorText := StrSubstNo('Failed to post journal line with Document No. %1 on Posting Date %2', GenJournalLine."Document No.", PostingDate);
                Message(ErrorText);
                exit(false);  // Exit if the post fails
            end;
        end;

        // Initialize and handle bank account entry (Credit)
        InitializeGenJournalLine(GenJournalLine, GenJournalBatch, LoanMaster, -DisbursementAmount, true, PostingDate);
        if PrepareOnly then
            GenJnlPostLine.RunWithCheck(GenJournalLine)  // Prepare: Validate and insert the journal line, but don't post
        else begin
            if not GenJnlPostLine.Run(GenJournalLine) then begin  // Post: Validate and post the journal line
                ErrorText := StrSubstNo('Failed to post journal line with Document No. %1 on Posting Date %2', GenJournalLine."Document No.", PostingDate);
                Message(ErrorText);
                exit(false);  // Exit if the post fails
            end;
        end;

        exit(true);  // Success
    end;


    local procedure InitializeGenJournalLine(var GenJournalLine: Record "Gen. Journal Line";
        GenJournalBatch: Record "Gen. Journal Batch"; LoanMaster: Record "Loan Master";
        Amount: Decimal; IsBankEntry: Boolean; PostingDate: Date)
    begin
        GenJournalLine.Reset();
        GenJournalLine.SetRange("Journal Template Name", GenJournalBatch."Journal Template Name");
        GenJournalLine.SetRange("Journal Batch Name", GenJournalBatch.Name);
        if GenJournalLine.FindLast() then
            GenJournalLine."Line No." += 10000
        else
            GenJournalLine."Line No." := 10000;

        GenJournalLine.Init();
        GenJournalLine.Validate("Journal Template Name", GenJournalBatch."Journal Template Name");
        GenJournalLine.Validate("Journal Batch Name", GenJournalBatch.Name);
        GenJournalLine.Validate("Posting Date", PostingDate);
        GenJournalLine.Validate("Document No.", Util.LoanDocNo(LoanMaster."Loan ID"));
        GenJournalLine.Validate("Account Type", IsBankEntry ? GenJournalLine."Account Type"::"Bank Account" : GenJournalLine."Account Type"::"G/L Account");
        GenJournalLine.Validate("Account No.", IsBankEntry ? Util.CheckingAccountNo() : Util.LoanAccountNo());
        GenJournalLine.Validate("Amount", Amount);
        GenJournalLine.Validate("Description", 'Loan Disbursement');
        GenJournalLine.Insert(true);
    end;

    local procedure FindDefaultJournalBatch(var GenJournalBatch: Record "Gen. Journal Batch"): Boolean
    begin
        GenJournalBatch.SetRange("Template Type", GenJournalBatch."Template Type"::General);
        GenJournalBatch.SetRange(Recurring, false);
        exit(GenJournalBatch.FindFirst());
    end;
}