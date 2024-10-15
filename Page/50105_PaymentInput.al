page 50105 PaymentInputPage
{
    PageType = StandardDialog;
    ApplicationArea = All;
    Caption = 'Post Payment';

    layout
    {
        area(content)
        {
            group(InputGroup)
            {
                field(NumberInputField; NumberInputField)
                {
                    ApplicationArea = All;
                    Caption = 'Enter the payment amount';
                    DecimalPlaces = 2 : 2;
                }
            }
        }
    }

    var
        NumberInputField: Decimal;

    procedure GetNumberInputField(): Decimal
    begin
        exit(NumberInputField);
    end;

    // Setter method to set the value of NumberInputField
    procedure SetNumberInputField(Value: Decimal)
    begin
        NumberInputField := Value;
    end;
}
