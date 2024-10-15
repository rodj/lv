table 50108 "Amount Filter Option"
{
    TableType = Temporary;

    fields
    {
        field(1; OptionValue; Enum "Amount Filter Option")
        {
            Caption = 'Option Value';
        }
        field(2; OptionName; Text[50])
        {
            Caption = 'Option Name';
        }
    }

    keys
    {
        key(PK; OptionValue)
        {
            Clustered = true;
        }
    }
}