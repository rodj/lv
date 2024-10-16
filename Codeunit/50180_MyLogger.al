codeunit 50180 "Logging Helper"
{
    procedure Log(SourceProcedure: Text[250]; LogMessage: Text[2048])
    var
        logRec: Record MyLog;
    begin
        logRec.Init();
        logRec.Id := 0;  // AutoIncrement
        logRec.CreateDate := CurrentDateTime;
        logRec.SrcPrc := SourceProcedure;
        logRec.Message := LogMessage;
        logRec.Insert(true);
    end;
}