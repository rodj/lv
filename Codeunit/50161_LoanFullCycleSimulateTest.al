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
    var
        LoanId: Code[20];
    begin
        MyTimestamp := Util.DayHourMinuteString();
        LoanId := 'L' + MyTimestamp;

        Util.Log('>> BEGIN: Manual Loan full test: ' + MyTimestamp, 'If no matching << END log with matching timestamp, something failed');

        Initialize();

        CreateValidLoan(LoanId, CustomerNo, LoanAmount, InterestRate, TermMonths, StartDate);

        DocNo := Util.LoanDocNo(LoanId);

        TestLoanDisbursement(LoanId);

        TestLoanRepayment(LoanId, 56.78);

        Util.Log('SUCCESS: Manual Loan full test');

        Cleanup('');

        Util.Log('<< END: Manual Loan full test');
        Message(Util.GetAllLogs());
    end;


    /// <summary>
    /// TODO: Refactor to eliminate duplicated code with TestLoanRepayment
    /// </summary>
    procedure TestLoanDisbursement(loanId: Code[20])
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
        DocumentNo := Util.LoanDocNo(LoanId);

        DataCleanup();

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

    procedure TestLoanRepayment(LoanId: Code[20]; RepaymentAmount: Decimal)
    var
        GenJournalLine: Record "Gen. Journal Line";
        GLEntry: Record "G/L Entry";
        BankAccountLedgerEntry: Record "Bank Account Ledger Entry";
        GenJournalBatch: Record "Gen. Journal Batch";
        GLAccount: Record "G/L Account";
        BankAccount: Record "Bank Account";
        InitialGLBalance: Decimal;
        InitialBankBalance: Decimal;
        DocumentNo: Text;
        Result: Boolean;
    begin
        DocumentNo := Util.LoanDocNo(LoanId);
        Util.Log(StrSubstNo('TestLoanRepayment started. LoanId: %1, Document No: %2, Repayment Amount: %3', LoanId, DocumentNo, RepaymentAmount), 'TestLoanRepayment');

        // Get initial balances
        GLAccount.Get(Util.LoanAccountNo());
        GLAccount.CalcFields("Balance at Date");
        InitialGLBalance := GLAccount."Balance at Date";
        BankAccount.Get(Util.CheckingAccountNo());
        BankAccount.CalcFields("Balance (LCY)");
        InitialBankBalance := BankAccount."Balance (LCY)";

        Util.Log(StrSubstNo('Initial balances - GL: %1, Bank: %2', InitialGLBalance, InitialBankBalance), 'TestLoanRepayment');

        Result := LoanJournalPosting.PostLoanRepayment(LoanMaster, RepaymentAmount, WorkDate());
        if not Result then begin
            Util.Log('Failed to post loan repayment journal entries', 'TestLoanRepayment');
            exit;
        end;

        Util.Log('Successfully posted journal entries', 'TestLoanRepayment');

        // Check for posted G/L Entries
        GLEntry.SetRange("Posting Date", WorkDate());
        GLEntry.SetRange("Document No.", DocumentNo);
        if GLEntry.FindSet() then begin
            repeat
                Util.Log(StrSubstNo('Posted G/L Entry: Account No.=%1, Amount=%2, Description=%3',
                                    GLEntry."G/L Account No.", GLEntry.Amount, GLEntry.Description), 'TestLoanRepayment');
            until GLEntry.Next() = 0;
        end else begin
            Util.Log('No G/L Entries found for the posted repayment', 'TestLoanRepayment');

            // Additional logging to investigate why entries are not found
            Util.Log(StrSubstNo('Searching for G/L Entries - Posting Date: %1, Document No: %2', WorkDate(), DocumentNo), 'TestLoanRepayment');

            GLEntry.Reset();
            if GLEntry.FindSet() then begin
                repeat
                    Util.Log(StrSubstNo('Found G/L Entry: Posting Date=%1, Document No=%2, Account No.=%3, Amount=%4',
                                        GLEntry."Posting Date", GLEntry."Document No.", GLEntry."G/L Account No.", GLEntry.Amount), 'TestLoanRepayment');
                until GLEntry.Next() = 0;
            end else
                Util.Log('No G/L Entries found at all', 'TestLoanRepayment');

            exit;
        end;

        // Check for posted Bank Account Ledger Entry
        BankAccountLedgerEntry.SetRange("Posting Date", WorkDate());
        BankAccountLedgerEntry.SetRange("Document No.", DocumentNo);
        if BankAccountLedgerEntry.FindSet() then begin
            repeat
                Util.Log(StrSubstNo('Posted Bank Account Ledger Entry: Bank Account No.=%1, Amount=%2, Description=%3',
                                    BankAccountLedgerEntry."Bank Account No.", BankAccountLedgerEntry.Amount, BankAccountLedgerEntry.Description), 'TestLoanRepayment');
            until BankAccountLedgerEntry.Next() = 0;
        end else begin
            Util.Log('No Bank Account Ledger Entries found for the posted repayment', 'TestLoanRepayment');
            exit;
        end;

        // Verify account balances have changed
        GLAccount.Get(Util.LoanAccountNo());
        GLAccount.CalcFields("Balance at Date");
        if GLAccount."Balance at Date" <> InitialGLBalance - RepaymentAmount then begin
            Util.Log(StrSubstNo('Incorrect G/L Account balance after posting. Expected %1, found %2',
                               InitialGLBalance - RepaymentAmount, GLAccount."Balance at Date"), 'TestLoanRepayment');
            exit;
        end;

        BankAccount.Get(Util.CheckingAccountNo());
        BankAccount.CalcFields("Balance (LCY)");
        if BankAccount."Balance (LCY)" <> InitialBankBalance + RepaymentAmount then begin
            Util.Log(StrSubstNo('Incorrect Bank Account balance after posting. Expected %1, found %2',
                               InitialBankBalance + RepaymentAmount, BankAccount."Balance (LCY)"), 'TestLoanRepayment');
            exit;
        end;

        Util.Log('Loan repayment test completed successfully', 'TestLoanRepayment');
    end;

    local procedure DataCleanup()
    var
        GenJournalLine: Record "Gen. Journal Line";
        GLEntry: Record "G/L Entry";
        BankAccountLedgerEntry: Record "Bank Account Ledger Entry";
        LoanAccount: Record "G/L Account";
        BankAccount: Record "Bank Account";
    begin
        Util.Log('Starting thorough cleanup', 'ThoroughCleanup');

        // Delete all General Journal Lines
        GenJournalLine.DeleteAll(true);
        Util.Log('Deleted all General Journal Lines', 'ThoroughCleanup');

        // Delete G/L Entries related to our loan account and bank account
        LoanAccount.Get(Util.LoanAccountNo());
        BankAccount.Get(Util.CheckingAccountNo());

        GLEntry.SetRange("G/L Account No.", LoanAccount."No.");
        GLEntry.DeleteAll(true);
        Util.Log(StrSubstNo('Deleted G/L Entries for Loan Account %1', LoanAccount."No."), 'ThoroughCleanup');

        GLEntry.SetRange("G/L Account No.", BankAccount."No.");
        GLEntry.DeleteAll(true);
        Util.Log(StrSubstNo('Deleted G/L Entries for Bank Account %1', BankAccount."No."), 'ThoroughCleanup');

        // Delete Bank Account Ledger Entries
        BankAccountLedgerEntry.SetRange("Bank Account No.", BankAccount."No.");
        BankAccountLedgerEntry.DeleteAll(true);
        Util.Log(StrSubstNo('Deleted Bank Account Ledger Entries for Bank Account %1', BankAccount."No."), 'ThoroughCleanup');

        // Reset balances
        LoanAccount.CalcFields("Balance at Date");
        LoanAccount."Balance at Date" := 0;
        LoanAccount.Modify(true);

        BankAccount.CalcFields("Balance at Date");
        BankAccount."Balance at Date" := 0;
        BankAccount.Modify(true);

        Util.Log('Reset account balances to zero', 'ThoroughCleanup');

        Util.Log('Thorough cleanup completed', 'ThoroughCleanup');
    end;

    local procedure LogAllJournalLines(GenJournalBatch: Record "Gen. Journal Batch")
    var
        GenJournalLine: Record "Gen. Journal Line";
    begin
        GenJournalLine.SetRange("Journal Template Name", GenJournalBatch."Journal Template Name");
        GenJournalLine.SetRange("Journal Batch Name", GenJournalBatch.Name);

        Util.Log(StrSubstNo('Logging journal lines for Template: %1, Batch: %2',
            GenJournalBatch."Journal Template Name", GenJournalBatch.Name), 'LogAllJournalLines');

        if GenJournalLine.FindSet() then
            repeat
                Util.Log(StrSubstNo('Journal Line: Template=%1, Batch=%2, Line=%3, Account=%4, DocNum=%5, PostingDate=%6, Amount=%7, Description=%8',
                    GenJournalLine."Journal Template Name",
                    GenJournalLine."Journal Batch Name",
                    GenJournalLine."Line No.",
                    GenJournalLine."Account No.",
                    GenJournalLine."Document No.",
                    GenJournalLine."Posting Date",
                    GenJournalLine.Amount,
                    GenJournalLine.Description), 'LogAllJournalLines');
            until GenJournalLine.Next() = 0
        else
            Util.Log('No journal lines found', 'LogAllJournalLines');

        Util.Log('End of journal lines log', 'LogAllJournalLines');
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

        DataCleanup();

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

        EnsureJournalSetup();

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

    local procedure EnsureJournalSetup()
    var
        GenJournalTemplate: Record "Gen. Journal Template";
        GenJournalBatch: Record "Gen. Journal Batch";
    begin
        if not GenJournalTemplate.Get('GENERAL') then begin
            GenJournalTemplate.Init();
            GenJournalTemplate.Name := 'GENERAL';
            GenJournalTemplate.Description := 'General';
            GenJournalTemplate.Type := GenJournalTemplate.Type::General;
            GenJournalTemplate.Insert();
            Util.Log('Created GENERAL journal template', 'EnsureJournalSetup');
        end;

        if not GenJournalBatch.Get('GENERAL', 'DAILY') then begin
            GenJournalBatch.Init();
            GenJournalBatch."Journal Template Name" := 'GENERAL';
            GenJournalBatch.Name := 'DAILY';
            GenJournalBatch.Description := 'Daily Batch';
            GenJournalBatch.Insert();
            Util.Log('Created DAILY batch in GENERAL template', 'EnsureJournalSetup');
        end;
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