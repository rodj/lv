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
        MyTimestamp: Text;
        DocNo: Text;

    procedure LoanFullCycle_TEST()
    begin
        MyTimestamp := Util.DayHourMinuteString();

        Util.Log('>> BEGIN: Manual Loan full test: ' + MyTimestamp, 'If no matching << END log with matching timestamp, something failed');

        LoanId := Initialize();

        CreateValidLoan(LoanId, CustomerNo, LoanAmount, InterestRate, TermMonths, StartDate);

        DocNo := Util.LoanDocNo(LoanId);

        TestLoanDisbursement(LoanId);

        TestLoanRepayment(LoanId, 56.78);

        Util.Log('SUCCESS: Manual Loan full test');

        Cleanup('');

        Util.Log('<< END: Manual Loan full test');
    end;

    /// <summary>
    /// TODO: Refactor to eliminate duplicated code with TestLoanRepayment
    /// </summary>
    procedure TestLoanDisbursement(loanId: Text)
    var
        GenJournalLine: Record "Gen. Journal Line";
        PostJournalEntries: Codeunit "Post Journal Entries";
        GLEntry: Record "G/L Entry";
        BankAccountLedgerEntry: Record "Bank Account Ledger Entry";
        GenJournalBatch: Record "Gen. Journal Batch";
        GLAccount: Record "G/L Account";
        BankAccount: Record "Bank Account";
        InitialGLBalance: Decimal;
        InitialBankBalance: Decimal;
        EntryCount: Integer;
        DocumentNo: Text;
        Result: Boolean;
        PrepareOnly: Boolean;
    begin
        CleanupPreviousTestEntries(loanId);

        DocumentNo := Util.LoanDocNo(LoanMaster."Loan ID");

        // Get initial balances
        GLAccount.Get(LoanAccountNo);
        GLAccount.CalcFields("Balance at Date");
        InitialGLBalance := GLAccount."Balance at Date";
        BankAccount.Get(CheckingAccountNo);
        BankAccount.CalcFields("Balance (LCY)");
        InitialBankBalance := BankAccount."Balance (LCY)";

        // Prepare journal entries
        PrepareOnly := true;
        Result := LoanJournalPosting.LoanDisbursementHandleEntries(PrepareOnly, LoanMaster, LoanMaster."Loan Amount", WorkDate);
        if not Result then begin
            Cleanup('Failed to prepare loan disbursement journal entries');
            exit;
        end;

        // Find the correct journal batch
        if not LoanJournalPosting.FindDefaultJournalBatch(GenJournalBatch) then begin
            Cleanup('Failed to find default journal batch');
            exit;
        end;

        // Post the prepared journal entries
        GenJournalLine.SetRange("Journal Template Name", GenJournalBatch."Journal Template Name");
        GenJournalLine.SetRange("Journal Batch Name", GenJournalBatch.Name);
        GenJournalLine.SetRange("Posting Date", WorkDate);
        GenJournalLine.SetRange("Document No.", DocumentNo);
        GenJournalLine.SetFilter(Amount, '<>0');

        EntryCount := GenJournalLine.Count();
        if EntryCount = 0 then begin
            Cleanup(StrSubstNo('No journal entries found to post. Template: %1, Batch: %2, Date: %3, Document No: %4',
                            GenJournalBatch."Journal Template Name", GenJournalBatch.Name, WorkDate, DocumentNo));
            exit;
        end;

        if GenJournalLine.FindSet() then begin
            Commit();  // Commit the transaction before posting
            CODEUNIT.RUN(CODEUNIT::"Gen. Jnl.-Post Batch", GenJournalLine);
            if GetLastErrorText() <> '' then begin
                Cleanup(StrSubstNo('Failed to post prepared journal entries. Error: %1', GetLastErrorText()));
                exit;
            end;
        end else begin
            Cleanup('No journal entries found to post after FindSet');
            exit;
        end;

        // Verify G/L Entries
        GLEntry.SetRange("Posting Date", WorkDate);
        GLEntry.SetRange("Document No.", DocumentNo);
        EntryCount := GLEntry.Count();
        if GLEntry.FindSet() then
            repeat
                Util.Log(StrSubstNo('G/L Entry: Account No.=%1, Posting Date=%2, Document No.=%3, Amount=%4, Description=%5',
                                    GLEntry."G/L Account No.",
                                    Format(GLEntry."Posting Date"),
                                    GLEntry."Document No.",
                                    Format(GLEntry.Amount),
                                    GLEntry.Description), 'TestLoanDisbursement');
            until GLEntry.Next() = 0
        else
            Util.Log('No G/L entries found matching the criteria', 'TestLoanDisbursement');

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

    procedure TestLoanRepayment(loanId: Text; RepaymentAmount: Decimal)
    var
        GenJournalLine: Record "Gen. Journal Line";
        GLEntry: Record "G/L Entry";
        BankAccountLedgerEntry: Record "Bank Account Ledger Entry";
        GenJournalBatch: Record "Gen. Journal Batch";
        GLAccount: Record "G/L Account";
        BankAccount: Record "Bank Account";
        InitialGLBalance: Decimal;
        InitialBankBalance: Decimal;
        EntryCount: Integer;
        DocumentNo: Text;
        Result: Boolean;
        PrepareOnly: Boolean;
    begin
        if RepaymentAmount <= 0 then
            Cleanup('Repayment amount must be greater than zero.');

        if RepaymentAmount > LoanMaster."Loan Amount" then
            Cleanup('Repayment amount cannot exceed the loan amount.');

        DocumentNo := Util.LoanDocNo(LoanMaster."Loan ID");

        // Get initial balances
        GLAccount.Get(LoanAccountNo);
        GLAccount.CalcFields("Balance at Date");
        InitialGLBalance := GLAccount."Balance at Date";
        BankAccount.Get(CheckingAccountNo);
        BankAccount.CalcFields("Balance (LCY)");
        InitialBankBalance := BankAccount."Balance (LCY)";

        // Prepare journal entries
        PrepareOnly := true;
        Result := LoanJournalPosting.PostLoanRepayment(LoanMaster, RepaymentAmount, WorkDate);
        if not Result then begin
            Cleanup('Failed to prepare loan repayment journal entries');
            exit;
        end;

        // Find the correct journal batch
        if not LoanJournalPosting.FindDefaultJournalBatch(GenJournalBatch) then begin
            Cleanup('Failed to find default journal batch');
            exit;
        end;

        // Post the prepared journal entries
        GenJournalLine.SetRange("Journal Template Name", GenJournalBatch."Journal Template Name");
        GenJournalLine.SetRange("Journal Batch Name", GenJournalBatch.Name);
        GenJournalLine.SetRange("Posting Date", WorkDate);
        GenJournalLine.SetRange("Document No.", DocumentNo);
        GenJournalLine.SetFilter(Amount, '<>0');

        EntryCount := GenJournalLine.Count();
        if EntryCount = 0 then begin
            Cleanup(StrSubstNo('No journal entries found to post. Template: %1, Batch: %2, Date: %3, Document No: %4',
                            GenJournalBatch."Journal Template Name", GenJournalBatch.Name, WorkDate, DocumentNo));
            exit;
        end;

        if GenJournalLine.FindSet() then begin
            Commit();  // Commit the transaction before posting
            CODEUNIT.RUN(CODEUNIT::"Gen. Jnl.-Post Batch", GenJournalLine);
            if GetLastErrorText() <> '' then begin
                Cleanup(StrSubstNo('Failed to post prepared journal entries. Error: %1', GetLastErrorText()));
                exit;
            end;
        end else begin
            Cleanup('No journal entries found to post after FindSet');
            exit;
        end;

        // Verify G/L Entries
        GLEntry.SetRange("Posting Date", WorkDate);
        GLEntry.SetRange("Document No.", DocumentNo);
        EntryCount := GLEntry.Count();
        if GLEntry.FindSet() then
            repeat
                Util.Log(StrSubstNo('G/L Entry: Account No.=%1, Posting Date=%2, Document No.=%3, Amount=%4, Description=%5',
                                    GLEntry."G/L Account No.",
                                    Format(GLEntry."Posting Date"),
                                    GLEntry."Document No.",
                                    Format(GLEntry.Amount),
                                    GLEntry.Description), 'TestLoanRepayment');
            until GLEntry.Next() = 0
        else
            Util.Log('No G/L entries found matching the criteria', 'TestLoanRepayment');

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
        if GLAccount."Balance at Date" <> InitialGLBalance - RepaymentAmount then begin
            Cleanup(StrSubstNo('Incorrect G/L Account balance after posting. Expected %1, found %2',
                               InitialGLBalance - RepaymentAmount, GLAccount."Balance at Date"));
            exit;
        end;

        BankAccount.Get(CheckingAccountNo);
        BankAccount.CalcFields("Balance (LCY)");
        if BankAccount."Balance (LCY)" <> InitialBankBalance + RepaymentAmount then begin
            Cleanup(StrSubstNo('Incorrect Bank Account balance after posting. Expected %1, found %2',
                               InitialBankBalance + RepaymentAmount, BankAccount."Balance (LCY)"));
            exit;
        end;

        // If we reach here, all checks passed
        Util.Log(StrSubstNo('Loan repayment test completed successfully for amount %1', RepaymentAmount));
    end;

    local procedure CleanupPreviousTestEntries(loanId: Text)
    var
        GenJournalLine: Record "Gen. Journal Line";
        GLEntry: Record "G/L Entry";
        BankAccountLedgerEntry: Record "Bank Account Ledger Entry";
        ReversalGLEntry: Record "G/L Entry";
        ReversalBankAccountLedgerEntry: Record "Bank Account Ledger Entry";
        EntryNo: Integer;
    begin
        // Delete any existing journal lines for this loan
        GenJournalLine.SetRange("Document No.", Util.LoanDocNo(loanId));
        GenJournalLine.DeleteAll();

        // Create reversal entries for G/L entries
        GLEntry.SetRange("Document No.", Util.LoanDocNo(loanId));
        if GLEntry.FindSet() then
            repeat
                ReversalGLEntry.Init();
                ReversalGLEntry.TransferFields(GLEntry);
                ReversalGLEntry."Entry No." := 0;  // Let the system assign a new Entry No.
                ReversalGLEntry."Document No." := Util.LoanDocNo(LoanMaster."Loan ID") + '-REV';
                ReversalGLEntry.Amount := -GLEntry.Amount;
                ReversalGLEntry."Debit Amount" := -GLEntry."Debit Amount";
                ReversalGLEntry."Credit Amount" := -GLEntry."Credit Amount";
                ReversalGLEntry."Posting Date" := WorkDate();
                ReversalGLEntry.Description := 'Reversal of ' + GLEntry.Description;
                ReversalGLEntry.Insert(true);
            until GLEntry.Next() = 0;

        // Create reversal entries for Bank Account Ledger entries
        BankAccountLedgerEntry.SetRange("Document No.", Util.LoanDocNo(loanId));
        if BankAccountLedgerEntry.FindSet() then
            repeat
                ReversalBankAccountLedgerEntry.Init();
                ReversalBankAccountLedgerEntry.TransferFields(BankAccountLedgerEntry);
                ReversalBankAccountLedgerEntry."Entry No." := 0;  // Let the system assign a new Entry No.
                ReversalBankAccountLedgerEntry."Document No." := Util.LoanDocNo(LoanMaster."Loan ID") + '-REV';
                ReversalBankAccountLedgerEntry.Amount := -BankAccountLedgerEntry.Amount;
                ReversalBankAccountLedgerEntry."Debit Amount" := -BankAccountLedgerEntry."Debit Amount";
                ReversalBankAccountLedgerEntry."Credit Amount" := -BankAccountLedgerEntry."Credit Amount";
                ReversalBankAccountLedgerEntry."Posting Date" := WorkDate();
                ReversalBankAccountLedgerEntry.Description := 'Reversal of ' + BankAccountLedgerEntry.Description;
                ReversalBankAccountLedgerEntry.Insert(true);
            until BankAccountLedgerEntry.Next() = 0;

        Util.Log('Cleanup completed for previous test entries', 'CleanupPreviousTestEntries');
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
        if UserMessage <> '' then begin
            Util.Log(UserMessage, 'Cleanup (Manual Test)');
            Message(UserMessage + '. This message is has been logged to MyLog');
        end;

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
    /// Returns LoanId to be used in test
    /// </summary>
    procedure Initialize(): Text
    var
        GenJournalLine: Record "Gen. Journal Line";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalTemplate: Record "Gen. Journal Template";
        GLSetup: Record "General Ledger Setup";
        TestLoanId: Text;
    begin
        WorkDate := DMY2Date(18, 11, 2023);

        TestLoanId := 'L' + Util.DayHourMinuteString();
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

        exit(TestLoanId);
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