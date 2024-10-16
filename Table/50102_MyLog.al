table 50100 "MyLog"
{
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Id"; Integer)
        {
            AutoIncrement = true;
        }
        field(2; "CreateDate"; DateTime)
        {
        }
        field(4; "SrcPrc"; Text[250])
        {
        }
        field(5; "Message"; Text[2048])
        {
        }
    }

    keys
    {
        key(PK; "Id")
        {
            Clustered = true;
        }
    }
}
