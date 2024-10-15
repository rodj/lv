codeunit 50170 "Post Journal Entries"
{
    procedure PostJournalEntries(var GenJournalLine: Record "Gen. Journal Line"): Boolean
    var
        GenJnlPostBatch: Codeunit "Gen. Jnl.-Post Batch";
    begin
        ClearLastError();
        GenJnlPostBatch.Run(GenJournalLine);
        exit(GetLastErrorText() = '');
    end;
}