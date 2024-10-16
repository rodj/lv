codeunit 50200 "Journal Posting Wrapper"
{
    procedure PostJournal(var GenJournalLine: Record "Gen. Journal Line"): Boolean
    var
        GenJnlPostBatch: Codeunit "Gen. Jnl.-Post Batch";
        Util: Codeunit Utility;
    begin
        Clear(GenJnlPostBatch);
        if not GenJnlPostBatch.Run(GenJournalLine) then begin
            Util.Log(StrSubstNo('Posting failed. Last Error: %1', GetLastErrorText), 'Journal Posting Wrapper');
            Util.Log(StrSubstNo('Journal Template: %1, Batch: %2', GenJournalLine."Journal Template Name", GenJournalLine."Journal Batch Name"), 'Journal Posting Wrapper');
            exit(false);
        end;
        exit(true);
    end;
}