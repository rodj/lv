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
        GenJournalTemplate: Record "Gen. Journal Template";
    begin
        Util.Log(StrSubstNo('Entering ProcessLoanTransaction. LoanID: %1, Amount: %2, Date: %3, Type: %4, PrepareOnly: %5',
                            LoanMaster."Loan ID", TransactionAmount, PostingDate, Format(TransactionType), PrepareOnly), 'ProcessLoanTransaction');

        if not LoanMaster.ValidateLoanMasterRecord() then
            exit(false);

        Util.GL_Setup();

        // Check G/L Setup for allowed posting dates
        GLSetup.Get();
        if (PostingDate < GLSetup."Allow Posting From") or (PostingDate > GLSetup."Allow Posting To") then begin
            Util.Log(StrSubstNo('Posting date %1 is outside the allowed posting range (%2 to %3)',
                PostingDate, GLSetup."Allow Posting From", GLSetup."Allow Posting To"), 'ProcessLoanTransaction');
            exit(false);
        end;

        // Check if the General Journal Template exists
        if not GenJournalTemplate.Get('GENERAL') then begin
            Util.Log('GENERAL journal template not found.', 'ProcessLoanTransaction');
            exit(false);
        end;

        // Find the default journal batch
        if not FindDefaultJournalBatch(GenJournalBatch) then begin
            Util.Log('No default journal batch found', 'ProcessLoanTransaction');
            exit(false);
        end;

        Util.Log(StrSubstNo('Using Journal Template: %1, Batch: %2', GenJournalBatch."Journal Template Name", GenJournalBatch.Name), 'ProcessLoanTransaction');

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

        Util.Log('Journal lines created. Logging current state:', 'ProcessLoanTransaction');
        LogJournalLines(GenJournalBatch);

        if GenJournalLine.IsEmpty then begin
            Util.Log('No journal lines were created', 'ProcessLoanTransaction');
            exit(false);
        end;

        Util.Log('Exiting ProcessLoanTransaction', 'ProcessLoanTransaction');
        exit(PostOrPrepareJournal(GenJournalBatch, PrepareOnly));
    end;

    local procedure LogJournalLines(GenJournalBatch: Record "Gen. Journal Batch")
    var
        GenJournalLine: Record "Gen. Journal Line";
    begin
        GenJournalLine.SetRange("Journal Template Name", GenJournalBatch."Journal Template Name");
        GenJournalLine.SetRange("Journal Batch Name", GenJournalBatch.Name);

        if GenJournalLine.FindSet() then
            repeat
                Util.Log(StrSubstNo('Journal Line: Template=%1, Batch=%2, Line=%3, Account=%4, DocNum=%5, PostingDate=%6, Amount=%7',
                                    GenJournalLine."Journal Template Name",
                                    GenJournalLine."Journal Batch Name",
                                    GenJournalLine."Line No.",
                                    GenJournalLine."Account No.",
                                    GenJournalLine."Document No.",
                                    GenJournalLine."Posting Date",
                                    GenJournalLine.Amount), 'LogJournalLines');
            until GenJournalLine.Next() = 0
        else
            Util.Log('No journal lines found', 'LogJournalLines');
    end;

    local procedure PostOrPrepareJournal(GenJournalBatch: Record "Gen. Journal Batch"; PrepareOnly: Boolean): Boolean
    var
        GenJournalLine: Record "Gen. Journal Line";
        GenJnlPostBatch: Codeunit "Gen. Jnl.-Post Batch";
    begin
        Util.Log(StrSubstNo('Entering PostOrPrepareJournal. PrepareOnly: %1, Template: %2, Batch: %3',
                            PrepareOnly, GenJournalBatch."Journal Template Name", GenJournalBatch.Name), 'PostOrPrepareJournal');

        GenJournalLine.SetRange("Journal Template Name", GenJournalBatch."Journal Template Name");
        GenJournalLine.SetRange("Journal Batch Name", GenJournalBatch.Name);

        Util.Log('Journal lines before preparation/posting:', 'PostOrPrepareJournal');
        LogJournalLines(GenJournalBatch);

        if PrepareOnly then begin
            // Just validate the lines
            if GenJournalLine.FindSet() then
                repeat
                    if not GenJournalLine.Modify(true) then begin
                        Util.Log(StrSubstNo('Failed to modify journal line. Line No: %1, Error: %2', GenJournalLine."Line No.", GetLastErrorText), 'PostOrPrepareJournal');
                        exit(false);
                    end;
                until GenJournalLine.Next() = 0;
            Util.Log('Journal lines prepared successfully', 'PostOrPrepareJournal');
        end else begin
            // Post the journal
            Commit();  // Commit any pending changes before posting
            if not GenJnlPostBatch.Run(GenJournalLine) then begin
                Util.Log(StrSubstNo('Failed to post the journal. Error: %1', GetLastErrorText), 'PostOrPrepareJournal');
                exit(false);
            end;
            Util.Log('Journal posted successfully', 'PostOrPrepareJournal');
        end;

        Util.Log('Journal lines after preparation/posting:', 'PostOrPrepareJournal');
        LogJournalLines(GenJournalBatch);

        Util.Log('Exiting PostOrPrepareJournal', 'PostOrPrepareJournal');
        exit(true);
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

        // Add logging
        Util.Log(StrSubstNo('Journal line created: Template=%1, Batch=%2, Line=%3, Account=%4, DocNum=%5, Amount=%6',
                            GenJournalLine."Journal Template Name",
                            GenJournalLine."Journal Batch Name",
                            GenJournalLine."Line No.",
                            GenJournalLine."Account No.",
                            GenJournalLine."Document No.",
                            GenJournalLine.Amount), 'CreateJournalLine');
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