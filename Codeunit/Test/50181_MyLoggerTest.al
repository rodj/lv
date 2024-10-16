codeunit 50181 "Logging Helper Test"
{
    Subtype = Test;

    var
        Assert: Codeunit "Library Assert";
        Logger: Codeunit "Logging Helper";

    [Test]
    procedure SingleEntry()
    var
        logRec: Record "MyLog";
        begRowCount: Integer;
        endRowCount: Integer;
    begin
        begRowCount := logRec.Count();
        Logger.Log('Test', 'Single Entry Test');
        endRowCount := logRec.Count();
        Assert.AreEqual(begRowCount + 1, endRowCount, 'Log entry should be added');
    end;
}