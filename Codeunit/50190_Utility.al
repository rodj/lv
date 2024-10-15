codeunit 50190 Utility
{
    /// <summary>
    /// Typically we would handle configuration like this in a more sophistictated manner
    /// but is fine for this exercise, main point is a single place to change
    /// Returns 'CHECKING'
    /// </summary>
    /// <returns>Code[20]</returns>
    procedure CheckingAccountNo(): Code[20]
    begin
        exit('CHECKING');
    end;

    procedure CreateLoanMaster(var LoanMaster: Record "Loan Master"; LoanID: Text)
    begin
        LoanMaster.Init();
        LoanMaster."Loan ID" := LoanID;
        LoanMaster.Insert();
    end;

    procedure DisplayOpenAccountingPeriods()
    var
        AccountingPeriod: Record "Accounting Period";
    begin
        AccountingPeriod.SetRange(Closed, false);
        if AccountingPeriod.FindSet() then begin
            repeat
                Message('Open Accounting Period: Start Date %1, New Fiscal Year: %2',
                    AccountingPeriod."Starting Date", AccountingPeriod."New Fiscal Year");
            until AccountingPeriod.Next() = 0;
        end else
            Message('No open accounting periods found.');
    end;

    procedure EnsureOpenAccountingPeriod(PostingDate: Date)
    var
        AccountingPeriod: Record "Accounting Period";
    begin
        AccountingPeriod.SetRange("Starting Date", 0D, PostingDate);
        AccountingPeriod.SetRange("New Fiscal Year", true);
        if not AccountingPeriod.FindLast() then begin
            AccountingPeriod.Init();
            AccountingPeriod."Starting Date" := CalcDate('<-CY>', PostingDate);
            AccountingPeriod."New Fiscal Year" := true;

            if not AccountingPeriod.Insert(false) then
                AccountingPeriod.Modify(true);
        end;
        AccountingPeriod.SetRange("Starting Date", AccountingPeriod."Starting Date", PostingDate);
        AccountingPeriod.ModifyAll(Closed, false);
    end;

    /// <summary>
    /// Typically we would handle configuration like this in a more sophistictated manner
    /// but is fine for this exercise, main point is a single place to change
    /// Returns '13300'
    /// </summary>
    /// <returns>Code[20]</returns>
    procedure LoanAccountNo(): Code[20]
    begin
        exit('13300');
    end;

    /// <summary>
    /// LRQ is entirely arbitrary
    /// Super simple for now, but by putting the logic in one place we
    /// can easily make it more sophisticated if necessary.
    /// Returns 'LRQ-' + "Loan ID"
    /// </summary>
    /// <returns>Code[20]</returns>
    procedure LoanDocNo(loanId: Text): Text
    begin
        exit('LRQ-' + loanId);
    end;

    procedure RandomDecimal(minVal: Decimal; maxVal: Decimal): Decimal
    var
        maxRand: Integer;
        factor: Decimal;
    begin
        // Arbitrarily choose 6 decimals of precision
        maxRand := 1000000;
        factor := Random(maxRand) / maxRand;

        exit(minVal + (maxVal - minVal) * factor);
    end;

    procedure ShortGuid(len: Integer): Text
    var
        guidStr: Text;
    begin
        if (len < 1) then
            Error('Utility.ShortGuid: len must be greater than 0');

        guidStr := Format(CreateGuid()).Replace('{', '').Replace('}', '').Replace('-', '');

        exit(CopyStr(guidStr, 1, len));
    end;

    procedure TestPostLoanRepaymentBasic()
    var
        LoanMaster: Record "Loan Master";
        RepaymentAmount: Decimal;
        PostingDate: Date;
        Result: Boolean;
        LoanJournalPosting: Codeunit "Loan Journal Posting";
        GLSetup: Record "General Ledger Setup";
    begin
        GL_Setup();
        Initialize();
        //CreateLoanMaster(LoanMaster);
        LoanMaster.Get('RODJ ONE');
        PostingDate := DMY2Date(18, 12, 2023);
        EnsureOpenAccountingPeriod(PostingDate);
        RepaymentAmount := 456.78;

        // Display current G/L Setup
        //Message('Allow Posting From: %1, Allow Posting To: %2', GLSetup."Allow Posting From", GLSetup."Allow Posting To");

        Result := LoanJournalPosting.PostLoanRepayment(LoanMaster, RepaymentAmount, PostingDate);

        VerifyJournalEntries(LoanMaster."Loan ID", RepaymentAmount, PostingDate);
    end;

    procedure GL_Setup()
    var
        GLSetup: Record "General Ledger Setup";
    begin
        // Ensure the posting date is within the allowed range
        GLSetup.Get();
        GLSetup."Allow Posting From" := DMY2Date(1, 1, 2015);
        GLSetup."Allow Posting To" := DMY2Date(31, 12, 2024);
        GLSetup.Modify();
    end;

    local procedure Initialize()
    var
        GenJournalLine: Record "Gen. Journal Line";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalTemplate: Record "Gen. Journal Template";
    begin
        GenJournalLine.DeleteAll();

        if not GenJournalTemplate.Get('GENERAL') then begin
            GenJournalTemplate.Init();
            GenJournalTemplate.Name := 'GENERAL';
            GenJournalTemplate.Description := 'General';
            GenJournalTemplate.Type := GenJournalTemplate.Type::General;
            GenJournalTemplate.Insert();
        end;

        if not GenJournalBatch.Get('GENERAL', 'DEFAULT') then begin
            GenJournalBatch.Init();
            GenJournalBatch."Journal Template Name" := 'GENERAL';
            GenJournalBatch.Name := 'DEFAULT';
            GenJournalBatch.Description := 'Default Batch';
            GenJournalBatch.Insert();
        end;
    end;

    local procedure VerifyJournalEntries(LoanID: Text; ExpectedAmount: Decimal; PostingDate: Date)
    var
        // Use this to check posted entries
        //GLEntry: Record "G/L Entry";

        // Use this to check expected entries
        GenJournalLine: Record "Gen. Journal Line";
        actualEntryCount: Integer;
    begin
        // Verify bank account entry. SetRange adds successive filters
        GenJournalLine.Reset();
        GenJournalLine.SetRange("Document No.", LoanDocNo(LoanID));
        //GLEntry.SetRange("G/L Account No.", CheckingAccountNo());
        GenJournalLine.SetRange("Account No.", CheckingAccountNo());
        GenJournalLine.SetRange("Posting Date", PostingDate);
        GenJournalLine.SetRange(Amount, ExpectedAmount);
        ActualEntryCount := GenJournalLine.Count();

        if actualEntryCount <> 1 then
            Message('Bank account entry count should be 1');

        // Verify loan receivable account entry
        GenJournalLine.Reset();
        GenJournalLine.SetRange("Document No.", LoanDocNo(LoanID));
        GenJournalLine.SetRange("Account No.", LoanAccountNo());  // Loan receivable account
        GenJournalLine.SetRange("Posting Date", PostingDate);
        GenJournalLine.SetRange(Amount, -ExpectedAmount);
        ActualEntryCount := GenJournalLine.Count();
        if actualEntryCount <> 1 then
            Message('Loan receivable account entry count should be 1');

    end;
}