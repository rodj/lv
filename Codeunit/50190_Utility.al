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

    procedure ClearAllLogs()
    var
        MyLog: Record "MyLog";
    begin
        MyLog.DeleteAll();
    end;

    procedure CreateLoanMaster(var LoanMaster: Record "Loan Master"; LoanID: Text)
    begin
        LoanMaster.Init();
        LoanMaster."Loan ID" := LoanID;
        LoanMaster.Insert();
    end;

    procedure CrLf(): Text
    var
        S: Text[2];
    begin
        S[1] := 13;
        S[2] := 10;
        exit(S);
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

    procedure GetAllLogs(): Text
    var
        MyLog: Record "MyLog";
        LogText: Text;
        CR: Text[2];
    begin
        CR := CrLf();

        if MyLog.FindSet() then
            repeat
                LogText += StrSubstNo('%1 | %2 | %3%4',
                                      Format(MyLog.CreateDate, 0, '<Year4>-<Month,2>-<Day,2> <Hours24,2>:<Minutes,2>:<Seconds,2>'),
                                      MyLog.SrcPrc,
                                      MyLog.Message,
                                      CR);
            until MyLog.Next() = 0
        else
            LogText := 'No log entries found.' + CR;

        exit(LogText);
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

    procedure Log(message: Text)
    begin
        Log(message, '');
    end;

    procedure Log(message: Text; srcPrc: Text)
    var
        logRec: Record MyLog;
    begin
        logRec.Init();
        logRec.Id := 0;  // AutoIncrement
        logRec.CreateDate := CurrentDateTime;
        logRec.SrcPrc := srcPrc;
        logRec.Message := message;
        logRec.Insert(true);
    end;

    /// <summary>
    /// Returns a formatted string of the current day, hour, and minute
    /// Example: for Jan 1, 2024 at 3:37pm, returns '011537'
    /// </summary>
    procedure DayHourMinuteString(): Text
    var
        CurrentDateTime: DateTime;
        CurrentDate: Date;
        CurrentTime: Time;
        FormattedString: Text[6];
        DayStr: Text[2];
        HourStr: Text[2];
        MinuteStr: Text[2];
    begin
        CurrentDateTime := CurrentDateTime();
        CurrentDate := DT2Date(CurrentDateTime); // Convert DateTime to Date
        CurrentTime := DT2Time(CurrentDateTime); // Convert DateTime to Time

        // Extract and format the day, hour, and minute
        DayStr := PadStr(Format(Date2DMY(CurrentDate, 1)), 2, '0');            // 2-digit day of the month with leading zero
        HourStr := PadStr(Format(CurrentTime, 0, '<Hours24>'), 2, '0');        // 2-digit hour (24-hour format) with leading zero
        MinuteStr := PadStr(Format(CurrentTime, 0, '<Minutes>'), 2, '0');      // 2-digit minute with leading zero

        // Combine into the final format DDHHmm
        FormattedString := DayStr + HourStr + MinuteStr;

        exit(FormattedString);
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