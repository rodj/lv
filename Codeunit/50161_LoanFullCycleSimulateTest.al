codeunit 50161 "Loan Full Cycle Simulate Test"
{
    // To make it executable
    Subtype = Normal;

    trigger OnRun()
    begin
        LoanFullCycle_TEST();
    end;

    var
        Util: Codeunit Utility;
        LoanMaster: Record "Loan Master";
        LoanJournalPosting: Codeunit "Loan Journal Posting";
        CustomerNo: Code[20];
        LoanId: Code[20];
        CheckingAccountNo: Code[20];
        LoanAccountNo: Code[20];
        LoanAmount: Decimal;
        PaymentAmount: Decimal;
        PaymentDate: Date;
        InterestRate: Decimal;
        TermMonths: Integer;
        StartDate: Date;

    procedure LoanFullCycle_TEST()
    begin
        Initialize();

        CreateValidLoan(LoanId, CustomerNo, LoanAmount, InterestRate, TermMonths, StartDate);

        TestLoanDisbursement();

        TestLoanRepayment();

        Cleanup('');
    end;

    procedure TestLoanRepayment()
    var
        GenJournalLine: Record "Gen. Journal Line";
        GLEntry: Record "G/L Entry";
        Result: Boolean;
    begin
        // Test repayment preparation
        Result := LoanJournalPosting.PostLoanRepayment(LoanMaster, PaymentAmount, PaymentDate);
        if not Result then
            Message('Failed to prepare loan repayment');

        // Verify account balances
        //VerifyAccountBalance(CheckingAccountNo, LoanAmount - PaymentAmount);
        //VerifyAccountBalance(LoanAccountNo, PaymentAmount - LoanAmount);
    end;

    procedure VerifyAccountBalance(AccountNo: Code[20]; ExpectedBalance: Decimal)
    var
        GLAccount: Record "G/L Account";
    begin
        GLAccount.Get(AccountNo);
        GLAccount.CalcFields(Balance);
        //todotestcodeAssert.AreEqual(ExpectedBalance, GLAccount.Balance, StrSubstNo('Incorrect balance for account %1', AccountNo));
    end;

    /// <summary>
    /// Cleans up the test environment by deleting the test loan and associated journal entries.
    /// Call whenever anything fails, or after success
    /// </summary>
    procedure Cleanup(UserMessage: Text)
    var
        GenJournalLine: Record "Gen. Journal Line";
        GLEntry: Record "G/L Entry";
        LoanId: Code[20];
        DocumentNo: Text;
        EntryCount: Integer;
    begin
        if UserMessage <> '' then
            Message(UserMessage);

        LoanId := LoanMaster."Loan ID";
        DocumentNo := Util.LoanDocNo(LoanMaster."Loan ID");

        // Delete test loan
        if LoanMaster.Get(LoanId) then
            LoanMaster.Delete(true);

        GenJournalLine.SetRange("Document No.", DocumentNo);
        EntryCount := GenJournalLine.Count();
        GenJournalLine.DeleteAll(true);

        GLEntry.SetRange("Document No.", DocumentNo);
        EntryCount := GenJournalLine.Count();
        GLEntry.DeleteAll(true);
    end;

    procedure TestLoanDisbursement()
    var
        GenJournalLine: Record "Gen. Journal Line";
        GenJnlPost: Codeunit "Gen. Jnl.-Post";
        GLEntry: Record "G/L Entry";
        BankAccountLedgerEntry: Record "Bank Account Ledger Entry";
        GLAccount: Record "G/L Account";
        BankAccount: Record "Bank Account";
        InitialGLBalance: Decimal;
        InitialBankBalance: Decimal;
        EntryCount: Integer;
        DocumentNo: Text;
        Result: Boolean;
    begin
        DocumentNo := Util.LoanDocNo(LoanMaster."Loan ID");

        // Get initial balances
        GLAccount.Get(LoanAccountNo);
        GLAccount.CalcFields("Balance at Date");
        InitialGLBalance := GLAccount."Balance at Date";
        BankAccount.Get(CheckingAccountNo);
        BankAccount.CalcFields("Balance (LCY)");
        InitialBankBalance := BankAccount."Balance (LCY)";

        // Prepare journal entries
        Result := LoanJournalPosting.LoanDisbursementPrepareEntries(LoanMaster, LoanMaster."Loan Amount", WorkDate);
        if not Result then begin
            Cleanup('Failed to prepare loan disbursement journal entries');
            exit;
        end;

        // Post the prepared journal entries
        GenJournalLine.SetRange("Journal Template Name", 'GENERAL');
        GenJournalLine.SetRange("Journal Batch Name", 'DAILY');
        GenJournalLine.SetRange("Posting Date", WorkDate);
        GenJournalLine.SetRange("Document No.", DocumentNo);
        if GenJournalLine.FindSet() then begin
            if not GenJnlPost.Run(GenJournalLine) then begin
                Cleanup('Failed to post prepared journal entries');
                exit;
            end;
        end else begin
            Cleanup('No journal entries found to post');
            exit;
        end;

        // Verify G/L Entries
        GLEntry.SetRange("Posting Date", WorkDate);
        GLEntry.SetRange("Document No.", DocumentNo);
        EntryCount := GLEntry.Count();
        if EntryCount <> 2 then begin
            Cleanup('Incorrect number of G/L entries');
            exit;
        end;
        GLEntry.FindFirst();

        // Verify Bank Account Ledger Entry
        BankAccountLedgerEntry.SetRange("Posting Date", WorkDate);
        BankAccountLedgerEntry.SetRange("Bank Account No.", CheckingAccountNo);
        if not BankAccountLedgerEntry.FindFirst() then begin
            Cleanup('No Bank Account Ledger Entry found');
            exit;
        end;

        // Verify account balances have changed
        GLAccount.Get(LoanAccountNo);
        GLAccount.CalcFields("Balance at Date");
        if GLAccount."Balance at Date" <> InitialGLBalance + LoanMaster."Loan Amount" then begin
            Cleanup(StrSubstNo('Incorrect G/L Account balance after posting. Expected %1, found %2',
                               InitialGLBalance + LoanMaster."Loan Amount", GLAccount."Balance at Date"));
            exit;
        end;

        BankAccount.Get(CheckingAccountNo);
        BankAccount.CalcFields("Balance (LCY)");
        if BankAccount."Balance (LCY)" <> InitialBankBalance - LoanMaster."Loan Amount" then begin
            Cleanup(StrSubstNo('Incorrect Bank Account balance after posting. Expected %1, found %2',
                               InitialBankBalance - LoanMaster."Loan Amount", BankAccount."Balance (LCY)"));
            exit;
        end;

        // If we reach here, all checks passed
        Message('Loan disbursement test completed successfully');
    end;

    procedure LogJournalLineDetails(var GenJournalLine: Record "Gen. Journal Line"): Text
    var
        LogOutput: Text;
        LogText: Text;
    begin
        Clear(LogOutput);

        if GenJournalLine.FindSet() then
            repeat
                LogText := StrSubstNo('Journal Line: Template=%1, Batch=%2, Line=%3, Account=%4, DocNum=%5, Bal Acct Typ=%6, Bal Acct No=%7, Amount=%8',
                    GenJournalLine."Journal Template Name",
                    GenJournalLine."Journal Batch Name",
                    GenJournalLine."Line No.",
                    GenJournalLine."Account No.",
                    GenJournalLine."Document No.",
                    GenJournalLine."Bal. Account Type",
                    GenJournalLine."Bal. Account No.",
                    GenJournalLine.Amount);
                if LogOutput <> '' then
                    LogOutput += '\';
                LogOutput += LogText;
            until GenJournalLine.Next() = 0;

        exit(LogOutput);
    end;

    procedure CreateValidLoan(loanId: Code[20]; custNo: Code[20]; amount: Decimal; rate: Decimal; term: Integer; startDate: Date)
    begin
        LoanMaster.Init();
        LoanMaster."Loan ID" := loanId;
        LoanMaster."Customer No." := custNo;
        LoanMaster."Loan Amount" := amount;
        LoanMaster."Interest Rate" := rate;
        LoanMaster."Loan Term" := term;
        LoanMaster."Start Date" := startDate;
        //todo9assertAssert.IsTrue(LoanMaster.Insert(true), 'Failed to insert valid loan');
    end;

    /// <summary>
    /// Sets values for loan under test (Amount, Id, Customer etc.)
    /// Also WorkDate, GenJournalTemplate, and GenJournalBatch
    /// </summary>
    procedure Initialize()
    var
        GenJournalLine: Record "Gen. Journal Line";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalTemplate: Record "Gen. Journal Template";
        GLSetup: Record "General Ledger Setup";
    begin
        WorkDate := DMY2Date(18, 11, 2023);

        LoanId := 'T1149'; // ~id
        CustomerNo := 'C00010';
        CheckingAccountNo := Util.CheckingAccountNo();
        LoanAccountNo := Util.LoanAccountNo();
        LoanAmount := 500000;
        InterestRate := 5;
        StartDate := 20231117D;
        TermMonths := 360;
        PaymentAmount := 12345.67;
        PaymentDate := 20231214D;

        if LoanMaster.Get(LoanId) then
            LoanMaster.Delete(true);

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

        GLSetup.Get();
        GLSetup."Allow Posting From" := DMY2Date(1, 1, 2023);
        GLSetup."Allow Posting To" := DMY2Date(31, 12, 2024);
        GLSetup.Modify();
    end;

    local procedure CreateLoanMaster(var LoanMaster: Record "Loan Master"; LoanID: Text)
    begin
        LoanMaster.Init();
        LoanMaster."Loan ID" := LoanID;
        LoanMaster.Insert();
    end;

    procedure DeleteAllJournalBatches()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
    begin
        GenJournalBatch.DeleteAll();
    end;

    procedure VerifyJournalEntries(LoanID: Text; ExpectedAmount: Decimal; PostingDate: Date)
    var
        // Use this to check posted entries
        //GLEntry: Record "G/L Entry";

        // Use this to check expected entries
        GenJournalLine: Record "Gen. Journal Line";
        actualEntryCount: Integer;
    begin
        // Verify bank account entry. SetRange adds successive filters
        GenJournalLine.Reset();
        GenJournalLine.SetRange("Document No.", Util.LoanDocNo(LoanID));
        //GLEntry.SetRange("G/L Account No.", CheckingAccountNo);
        GenJournalLine.SetRange("Account No.", CheckingAccountNo);
        GenJournalLine.SetRange("Posting Date", PostingDate);
        GenJournalLine.SetRange(Amount, ExpectedAmount);
        ActualEntryCount := GenJournalLine.Count();
        //todotestcodeAssert.AreEqual(1, ActualEntryCount, 'Bank account entry count should be 1');

        // Verify loan receivable account entry
        GenJournalLine.Reset();
        GenJournalLine.SetRange("Document No.", Util.LoanDocNo(LoanID));
        //GLEntry.SetRange("G/L Account No.", LoanAccountNo);
        GenJournalLine.SetRange("Account No.", LoanAccountNo);  // Loan receivable account
        GenJournalLine.SetRange("Posting Date", PostingDate);
        GenJournalLine.SetRange(Amount, -ExpectedAmount);
        actualEntryCount := GenJournalLine.Count();
        //todotestcodeAssert.AreEqual(1, actualEntryCount, 'There should be exactly one loan receivable account entry');
    end;
}