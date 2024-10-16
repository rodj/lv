pageextension 50105 "Business Manager RC Ext" extends "Business Manager Role Center"
{
    // Adds a new main menu option
    actions
    {
        addlast(sections)
        {
            group(Loans)
            {
                Caption = 'Loans';

                action(LoanMasterList)
                {
                    ApplicationArea = All;
                    Caption = 'Loans';
                    RunObject = Page "Loan Master List";
                    ToolTip = 'View and manage loans';
                }

                action(Test)
                {
                    ApplicationArea = All;
                    Caption = 'Test!';
                    ToolTip = 'Run Loan Full Cycle Test';
                    RunObject = Codeunit "Loan Full Cycle Simulate Test";
                }
            }

            group(MyLog)
            {
                Caption = 'MyLog';

                action(Log)
                {
                    ApplicationArea = All;
                    Caption = 'Log';
                    ToolTip = 'Custom Log';
                    RunObject = Page "Log List";
                }
            }
        }
    }
}