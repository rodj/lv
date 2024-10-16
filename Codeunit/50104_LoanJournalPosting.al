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
        GenJournalLine: Record "Gen. Journal Line";
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

        // Clear existing lines in the batch
        GenJournalLine.SetRange("Journal Template Name", GenJournalBatch."Journal Template Name");
        GenJournalLine.SetRange("Journal Batch Name", GenJournalBatch.Name);
        GenJournalLine.DeleteAll();
        if not GenJournalLine.IsEmpty then begin
            Util.Log('Failed to clear existing journal lines', 'ProcessLoanTransaction');
            exit(false);
        end;

        // Create balanced entries
        case TransactionType of
            "Loan Transaction Type"::Disbursement:
                begin
                    CreateJournalLine(GenJournalLine, GenJournalBatch, LoanMaster, TransactionAmount, false, PostingDate);
                    CreateJournalLine(GenJournalLine, GenJournalBatch, LoanMaster, -TransactionAmount, true, PostingDate);
                end;
            "Loan Transaction Type"::Repayment:
                begin
                    CreateJournalLine(GenJournalLine, GenJournalBatch, LoanMaster, TransactionAmount, true, PostingDate);
                    CreateJournalLine(GenJournalLine, GenJournalBatch, LoanMaster, -TransactionAmount, false, PostingDate);
                end;
        end;

        if GenJournalLine.IsEmpty then begin
            Util.Log('No journal lines were created', 'ProcessLoanTransaction');
            exit(false);
        end;

        exit(PostOrPrepareJournal(GenJournalBatch, PrepareOnly));
    end;

    local procedure CreateJournalLine(var GenJournalLine: Record "Gen. Journal Line"; GenJournalBatch: Record "Gen. Journal Batch"; LoanMaster: Record "Loan Master"; Amount: Decimal; IsBankEntry: Boolean; PostingDate: Date)
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

    local procedure PostOrPrepareJournal(GenJournalBatch: Record "Gen. Journal Batch"; PrepareOnly: Boolean): Boolean
    var
        GenJournalLine: Record "Gen. Journal Line";
        GenJnlPostBatch: Codeunit "Gen. Jnl.-Post Batch";
        GenJournalTemplate: Record "Gen. Journal Template";
        Logger: Record "MyLog";
        LineCount: Integer;
        LineDetails: Text;
        CurrLine: Text;
        crlf: Text;
    begin
        crlf := Util.CrLf();

        Util.Log('---------------------------------', '');

        if not GenJournalTemplate.Get('GENERAL') then begin
            Util.Log('GENERAL journal template not found.');
            exit(false);
        end;

        if not GenJournalBatch.Get('GENERAL', 'DAILY') then begin
            Util.Log('DAILY batch not found in GENERAL template.');
            exit(false);
        end;

        Util.Log(StrSubstNo('Using Journal Template: %1, Batch: %2', GenJournalBatch."Journal Template Name", GenJournalBatch.Name));

        GenJournalLine.SetRange("Journal Template Name", GenJournalBatch."Journal Template Name");
        GenJournalLine.SetRange("Journal Batch Name", GenJournalBatch.Name);
        GenJournalLine.SetFilter(Amount, '<>0');  // Filter out the bogus empty line auto-added by the system

        if not GenJournalLine.FindSet() then begin
            Util.Log('No journal lines found for the specified batch.');
            exit(false);
        end;

        repeat
            LineCount += 1;
            CurrLine := StrSubstNo('Line %1:%2' +
                                      'Account Type: %3%2' +
                                      'Account No.: %4%2' +
                                      'Posting Date: %5%2' +
                                      'Document Type: %6%2' +
                                      'Document No.: %7%2' +
                                      'Description: %8%2' +
                                      'Amount: %9%2',
                                      LineCount,
                                      crlf,
                                      GenJournalLine."Account Type",
                                      GenJournalLine."Account No.",
                                      Format(GenJournalLine."Posting Date"),
                                      GenJournalLine."Document Type",
                                      GenJournalLine."Document No.",
                                      GenJournalLine.Description,
                                      Format(GenJournalLine.Amount));

            LineDetails += CurrLine;
            Util.Log(CurrLine, 'PostOrPrepareJournal');
        until GenJournalLine.Next() = 0;

        //Util.Log(LineDetails, 'PostOrPrepareJournal');

        Util.Log('---------------------------------');

        if PrepareOnly then begin
            // Just validate the lines
            if not GenJournalLine.Modify(true) then begin
                Util.Log(StrSubstNo('Failed to insert journal line. Line No: %1, Error: %2', GenJournalLine."Line No.", GetLastErrorText), '');
                exit(false);
            end;
        end else begin
            // Post the journal
            CODEUNIT.RUN(CODEUNIT::"Gen. Jnl.-Post Batch", GenJournalLine);
            if GetLastErrorText() <> '' then begin
                Util.Log(StrSubstNo('Failed to post the journal. Error: %1', GetLastErrorText()), '');
                exit(false);
            end;
        end;

        exit(true);
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

    procedure FindDefaultJournalBatch(var GenJournalBatch: Record "Gen. Journal Batch"): Boolean
    var
        GenJournalTemplate: Record "Gen. Journal Template";
    begin
        /*
        if not GenJournalTemplate.FindFirst() then
            exit(false);

        GenJournalBatch.SetRange("Journal Template Name", GenJournalTemplate.Name);
        GenJournalBatch.SetRange(Recurring, false);
        exit(GenJournalBatch.FindFirst());
        */
        exit(GenJournalBatch.Get('GENERAL', 'DAILY'));
    end;
}