codeunit 50105 "Loan Journal Posting Tests"
{
    Subtype = Test;

    var
        Assert: Codeunit "Library Assert";
        Util: Codeunit Utility;
        LoanJournalPosting: Codeunit "Loan Journal Posting";

    [Test]
    procedure TestPostLoanRepaymentBasic()
    var
        LoanMaster: Record "Loan Master";
        PaymentAmount: Decimal;
        PostingDate: Date;
        Result: Boolean;
    begin
        // [GIVEN] A clean environment with a loan master record
        Initialize();
        CreateLoanMaster(LoanMaster);
        PostingDate := DMY2Date(17, 11, 2023);
        Util.EnsureOpenAccountingPeriod(PostingDate);
        PaymentAmount := 123.45;

        // [WHEN] PostLoanRepayment is called
        Result := LoanJournalPosting.PostLoanRepayment(LoanMaster, PaymentAmount, PostingDate);

        // [THEN] The function returns true
        Assert.IsTrue(Result, 'PostLoanRepayment should return true');

        // [THEN] verify the journal entries were indeed created
        VerifyJournalEntries(LoanMaster."Loan ID", PaymentAmount, PostingDate);
    end;

    [Test]
    procedure TestPostLoanRepaymentWithNoDefaultBatch()
    var
        LoanMaster: Record "Loan Master";
        RepaymentAmount: Decimal;
    begin
        // [GIVEN] A clean environment
        Initialize();

        // [GIVEN] A loan master record and a repayment amount
        CreateLoanMaster(LoanMaster);
        RepaymentAmount := Util.RandomDecimal(100, 100000);

        // [GIVEN] No default journal batch exists
        DeleteAllJournalBatches();

        // [WHEN] PostLoanRepayment is called
        // [THEN] An error is thrown
        asserterror LoanJournalPosting.PostLoanRepayment(LoanMaster, RepaymentAmount, DMY2Date(3, 11, 2023));
        Assert.ExpectedError('No default journal batch found');
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

    local procedure CreateLoanMaster(var LoanMaster: Record "Loan Master")
    begin
        LoanMaster.Init();
        LoanMaster."Loan ID" := Util.ShortGuid(10);
        LoanMaster.Insert();
    end;

    local procedure DeleteAllJournalBatches()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
    begin
        GenJournalBatch.DeleteAll();
    end;

    local procedure VerifyJournalEntries(LoanID: Text; ExpectedAmount: Decimal; PostingDate: Date)
    var
        //GLEntry: Record "G/L Entry";
        GenJnlLine: Record "Gen. Journal Line";
        ActualEntryCount: Integer;
    begin
        // Verify bank account entry. SetRange adds successive filters
        GenJnlLine.Reset();
        GenJnlLine.SetRange("Document No.", Util.LoanDocNo(LoanID));
        //GLEntry.SetRange("G/L Account No.", Util.CheckingAccountNo());
        GenJnlLine.SetRange("Account No.", Util.CheckingAccountNo());
        GenJnlLine.SetRange("Posting Date", PostingDate);
        GenJnlLine.SetRange(Amount, ExpectedAmount);
        Assert.AreEqual(1, ActualEntryCount, 'Bank account entry count should be 1');

        // Verify loan receivable account entry
        GenJnlLine.Reset();
        GenJnlLine.SetRange("Document No.", Util.LoanDocNo(LoanID));
        //GLEntry.SetRange("G/L Account No.", Util.LoanAccountNo());
        GenJnlLine.SetRange("Account No.", Util.LoanAccountNo());
        GenJnlLine.SetRange("Posting Date", PostingDate);
        GenJnlLine.SetRange(Amount, -ExpectedAmount);
        Assert.AreEqual(1, actualEntryCount, 'There should be exactly one loan receivable account entry');
    end;
}