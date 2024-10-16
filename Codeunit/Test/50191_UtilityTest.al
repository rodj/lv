codeunit 50191 "Utility Tests"
{
    Subtype = Test;

    var
        Assert: Codeunit "Library Assert";
        Util: Codeunit Utility;

    [Test]
    procedure RandomDecimal_TESTS()
    begin
        RunRandomDecimalCase(1, 100);
        RunRandomDecimalCase(-100, 100);
        RunRandomDecimalCase(1234.5678, 234567.89)
    end;

    local procedure RunRandomDecimalCase(MinValue: Decimal; MaxValue: Decimal)
    var
        Actual: Decimal;
    begin
        Actual := Util.RandomDecimal(MinValue, MaxValue);
        Assert.IsTrue((Actual >= MinValue) and (Actual <= MaxValue), 'RandomDecimal should return a value between MinValue and MaxValue');
    end;

    [Test]
    procedure ShortGuid_TESTS()
    begin
        RunShortGuidCase(1, 1);
        RunShortGuidCase(2, 2);
        RunShortGuidCase(10, 10);
        RunShortGuidCase(101, 32);
    end;

    local procedure RunShortGuidCase(len: Integer; expectedLen: Integer)
    var
        Actual: Text;
    begin
        Actual := Util.ShortGuid(len);
        Assert.AreEqual(expectedLen, StrLen(Actual), 'ShortGuid should return a string of length len');
    end;

    [Test]
    procedure TestEnsureOpenAccountingPeriod_NewPeriod()
    var
        AccountingPeriod: Record "Accounting Period";
        TestDate: Date;
    begin
        // [GIVEN] A date in a future period
        TestDate := DMY2Date(1, 11, 2023);  // November 1, 2023

        // [WHEN] EnsureOpenAccountingPeriod is called
        Util.EnsureOpenAccountingPeriod(TestDate);

        // [THEN] An open accounting period should exist for the test date
        AccountingPeriod.SetRange("Starting Date", CalcDate('<-CY>', TestDate), TestDate);
        AccountingPeriod.SetRange(Closed, false);
        Assert.RecordIsNotEmpty(AccountingPeriod);
    end;

    [Test]
    procedure TestEnsureOpenAccountingPeriod_ExistingClosedPeriod()
    var
        AccountingPeriod: Record "Accounting Period";
        TestDate: Date;
    begin
        // [GIVEN] An existing closed accounting period
        TestDate := DMY2Date(1, 12, 2023);  // December 1, 2023
        CreateClosedAccountingPeriod(TestDate);

        // [WHEN] EnsureOpenAccountingPeriod is called
        Util.EnsureOpenAccountingPeriod(TestDate);

        // [THEN] The accounting period should be open
        AccountingPeriod.SetRange("Starting Date", CalcDate('<-CY>', TestDate), TestDate);
        AccountingPeriod.SetRange(Closed, false);
        Assert.RecordIsNotEmpty(AccountingPeriod);
    end;

    [Test]
    procedure TestEnsureOpenAccountingPeriod_MultipleCallsSameDate()
    var
        AccountingPeriod: Record "Accounting Period";
        TestDate: Date;
        InitialCount: Integer;
        FinalCount: Integer;
    begin
        // [GIVEN] A test date
        TestDate := DMY2Date(1, 1, 2024);  // January 1, 2024

        // [WHEN] EnsureOpenAccountingPeriod is called multiple times
        Util.EnsureOpenAccountingPeriod(TestDate);
        AccountingPeriod.SetRange("Starting Date", 0D, TestDate);
        InitialCount := AccountingPeriod.Count;

        Util.EnsureOpenAccountingPeriod(TestDate);
        Util.EnsureOpenAccountingPeriod(TestDate);

        // [THEN] No additional periods should be created
        AccountingPeriod.SetRange("Starting Date", 0D, TestDate);
        FinalCount := AccountingPeriod.Count;
        Assert.AreEqual(InitialCount, FinalCount, 'No additional periods should be created');
    end;

    local procedure CreateClosedAccountingPeriod(StartDate: Date)
    var
        AccountingPeriod: Record "Accounting Period";
    begin
        AccountingPeriod.SetRange("Starting Date", CalcDate('<-CY>', StartDate), StartDate);
        if not AccountingPeriod.FindFirst() then begin
            AccountingPeriod.Init();
            AccountingPeriod."Starting Date" := CalcDate('<-CY>', StartDate);
            AccountingPeriod."New Fiscal Year" := true;
            AccountingPeriod.Closed := true;
            AccountingPeriod.Insert(false);
        end else begin
            AccountingPeriod.Closed := true;
            AccountingPeriod.Modify(true);
        end;
    end;
}