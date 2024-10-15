table 50102 "Loan Master"
{
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Loan ID"; Code[20])
        {
            Caption = 'Loan ID';
            DataClassification = CustomerContent;
        }
        field(2; "Customer No."; Code[20])
        {
            Caption = 'Customer No.';
            DataClassification = CustomerContent;
            TableRelation = Customer."No.";

            trigger OnValidate()
            begin
                CalcFields("Customer Name");
            end;
        }
        field(3; "Customer Name"; Text[100])
        {
            Caption = 'Customer Name';
            FieldClass = FlowField;
            CalcFormula = LOOKUP(Customer.Name WHERE("No." = FIELD("Customer No.")));
            Editable = false;
        }
        field(4; "Loan Amount"; Decimal)
        {
            Caption = 'Loan Amount';
            DataClassification = CustomerContent;
            MinValue = 0.01;
            MaxValue = ConfigMaxLoanAmount;

            trigger OnValidate()
            begin
                InitializeConstants();
                AmountValidate('Loan Amount', ConfigMaxLoanAmount);
                CalculateMonthlyPayment();
            end;
        }
        field(5; "Interest Rate"; Decimal)
        {
            Caption = 'Interest Rate';
            DataClassification = CustomerContent;
            MinValue = 0.01;
            MaxValue = ConfigMaxInterestRate;

            trigger OnValidate()
            begin
                InitializeConstants();
                AmountValidate('Interest Rate', ConfigMaxInterestRate);
                CalculateMonthlyPayment();
            end;
        }
        field(6; "Loan Term"; Integer)
        {
            Caption = 'Loan Term (Months)';
            DataClassification = CustomerContent;
            MinValue = 1;
            MaxValue = ConfigMaxLoanTerm;

            trigger OnValidate()
            begin
                InitializeConstants();
                AmountValidate('Loan Term', ConfigMaxLoanTerm);
                CalculateMonthlyPayment();
                UpdateEndDate();
            end;
        }
        field(7; "Start Date"; Date)
        {
            Caption = 'Start Date';
            DataClassification = CustomerContent;

            trigger OnValidate()
            begin
                UpdateEndDate();
            end;
        }
        field(8; "End Date"; Date)
        {
            Caption = 'End Date';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(9; "Monthly Payment"; Decimal)
        {
            Caption = 'Monthly Payment';
            DataClassification = CustomerContent;
            Editable = false;
        }
    }

    keys
    {
        key(PK; "Loan ID")
        {
            Clustered = true;
        }
    }

    var
        Util: Codeunit "Utility";
        ConfigMinLoanAmount: Decimal;
        ConfigMaxLoanAmount: Decimal;
        ConfigMinInterestRate: Decimal;
        ConfigMaxInterestRate: Decimal;
        ConfigMinLoanTerm: Integer;
        ConfigMaxLoanTerm: Integer;

    trigger OnInsert()
    begin
        InitializeConstants();
        if ("Loan ID" = '') then
            "Loan ID" := Util.ShortGuid(10);
    end;

    local procedure InitializeConstants()
    begin
        ConfigMinLoanAmount := 0.01;
        ConfigMaxLoanAmount := 10000000;
        ConfigMinInterestRate := 0.01;
        ConfigMaxInterestRate := 50;
        ConfigMinLoanTerm := 1;
        ConfigMaxLoanTerm := 600;  // 50 years
    end;

    local procedure AmountValidate(FieldName: Text; MaxAmount: Decimal)
    var
        FieldValue: Decimal;
    begin
        FieldValue := GetFieldValue(FieldName);
        if FieldValue <= 0 then
            Error('%1 must be greater than 0', FieldName);
        if FieldValue > MaxAmount then
            Error('%1 must be less than or equal to %2', FieldName, MaxAmount);
    end;

    procedure GetFieldValue(FieldName: Text): Decimal
    var
        RecRef: RecordRef;
        FldRef: FieldRef;
        i: Integer;
        AsDecimal: Decimal;
    begin
        RecRef.GetTable(Rec);

        for i := 1 to RecRef.FieldCount do begin
            FldRef := RecRef.FieldIndex(i);
            if FldRef.Name = FieldName then begin
                if Evaluate(AsDecimal, Format(FldRef.Value)) then
                    exit(AsDecimal);
            end
        end;

        Error('Field %1 does not exist in table %2', FieldName, RecRef.Caption);
    end;

    procedure ValidateLoanMasterRecord(): Boolean
    var
        errText: Text;
    begin
        InitializeConstants();

        ClearLastError();

        TestField("Loan ID");
        TestField("Customer No.");
        Validate("Loan Amount");
        Validate("Interest Rate");
        Validate("Loan Term");
        TestField("Start Date");

        errText := GetLastErrorText();

        exit(errText = '');
    end;

    local procedure CalculateMonthlyPayment()
    var
        LoanCalc: Codeunit "Loan Calculations";
    begin
        "Monthly Payment" := LoanCalc.MonthlyPayment("Loan Amount", "Interest Rate", "Loan Term");
        "Monthly Payment" := Round("Monthly Payment", 0.01);
    end;

    local procedure UpdateEndDate()
    begin
        if ("Start Date" <> 0D) and ("Loan Term" > 0) then
            "End Date" := CalcDate('<' + Format("Loan Term") + 'M>', "Start Date");
    end;
}