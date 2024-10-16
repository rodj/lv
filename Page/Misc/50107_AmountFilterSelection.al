page 50107 "Amount Filter Selection"
{
    PageType = List;
    Caption = 'Select Amount Range';
    SourceTable = "Amount Filter Option";
    SourceTableTemporary = true;
    InsertAllowed = false;
    DeleteAllowed = false;
    ModifyAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Options)
            {
                field(OptionName; Rec.OptionName)
                {
                    ApplicationArea = All;
                    Caption = 'Filter Option';

                    trigger OnDrillDown()
                    begin
                        SelectFilter(Rec.OptionValue);
                    end;
                }
            }
        }
    }

    var
        SelectedFilterOption: Enum "Amount Filter Option";
        IsFilterSelected: Boolean;

    trigger OnOpenPage()
    begin
        LoadOptions();
        IsFilterSelected := false;
    end;

    local procedure LoadOptions()
    begin
        Rec.DeleteAll();

        Rec.Init();
        Rec.OptionValue := Rec.OptionValue::All_Amounts;
        Rec.OptionName := 'All Amounts';
        Rec.Insert();

        Rec.Init();
        Rec.OptionValue := Rec.OptionValue::To100k;
        Rec.OptionName := 'Up to 100k';
        Rec.Insert();

        Rec.Init();
        Rec.OptionValue := Rec.OptionValue::Amt100kToMil;
        Rec.OptionName := '100k to 1 million';
        Rec.Insert();

        Rec.Init();
        Rec.OptionValue := Rec.OptionValue::Over1Mil;
        Rec.OptionName := 'Over 1 million';
        Rec.Insert();
    end;

    local procedure SelectFilter(SelectedFilter: Enum "Amount Filter Option")
    begin
        SelectedFilterOption := SelectedFilter;
        IsFilterSelected := true;
        CurrPage.Close();
    end;

    procedure GetSelectedFilter(): Enum "Amount Filter Option"
    begin
        exit(SelectedFilterOption);
    end;

    procedure WasFilterSelected(): Boolean
    begin
        exit(IsFilterSelected);
    end;
}