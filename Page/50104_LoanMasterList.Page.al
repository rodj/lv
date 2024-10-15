page 50104 "Loan Master List"
{
    PageType = List;
    ApplicationArea = All;
    UsageCategory = Lists;
    SourceTable = "Loan Master";
    CardPageId = "Loan Master Card";
    Caption = 'Loans';

    layout
    {
        area(Content)
        {
            repeater(GroupName)
            {
                field("Loan ID"; Rec."Loan ID")
                {
                    ApplicationArea = All;
                }
                field("Cust No."; Rec."Customer No.")
                {
                    ApplicationArea = All;
                }
                field("Cust Name"; Rec."Customer Name")
                {
                    ApplicationArea = All;
                }
                field("Loan Amount"; Rec."Loan Amount")
                {
                    ApplicationArea = All;
                }
                field("Interest Rate"; Rec."Interest Rate")
                {
                    ApplicationArea = All;
                }
                field("Loan Term"; Rec."Loan Term")
                {
                    ApplicationArea = All;
                }
                field("Start Date"; Rec."Start Date")
                {
                    ApplicationArea = All;
                }
                field("Monthly Payment"; Rec."Monthly Payment")
                {
                    ApplicationArea = All;
                }
            }
        }
        area(Factboxes)
        {
            part(CustomerDetails; "Customer Details FactBox")
            {
                SubPageLink = "No." = FIELD("Customer No.");
                ApplicationArea = All;
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(ClickMeButton)
            {
                ApplicationArea = All;
                Caption = 'Sort by Amount (Desc)';
                Image = Sort;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;

                trigger OnAction()
                begin
                    Rec.SetCurrentKey("Loan Amount");
                    Rec.Ascending(false);
                    CurrPage.SetTableView(Rec);
                    CurrPage.Update(false);
                end;
            }

            action(AmountFilter)
            {
                ApplicationArea = All;
                Caption = 'Filter by Amount';
                Image = FilterLines;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;

                trigger OnAction()
                var
                    AmountFilterDialog: Page "Amount Filter Selection";
                    SelectedFilter: Enum "Amount Filter Option";
                begin
                    AmountFilterDialog.RunModal();
                    if AmountFilterDialog.WasFilterSelected() then begin
                        SelectedFilter := AmountFilterDialog.GetSelectedFilter();
                        Rec.Reset();
                        Rec.SetFilter("Loan Amount", '');

                        case SelectedFilter of
                            SelectedFilter::All_Amounts:
                                Rec.SetRange("Loan Amount");
                            SelectedFilter::To100k:
                                Rec.SetRange("Loan Amount", 0, 100000);
                            SelectedFilter::Amt100kToMil:
                                Rec.SetRange("Loan Amount", 100000, 1000000);
                            SelectedFilter::Over1Mil:
                                Rec.SetFilter("Loan Amount", '>%1', 1000000);
                        end;

                        CurrPage.SetTableView(Rec);
                        CurrPage.Update(false);
                    end;
                end;
            }

            action(FilterByCustomer)
            {
                ApplicationArea = All;
                Caption = 'Filter by Customer';
                Image = Customer;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;

                trigger OnAction()
                var
                    Customer: Record Customer;
                    CustomerLookup: Page "Customer Lookup";
                begin
                    CustomerLookup.LookupMode(true);
                    if CustomerLookup.RunModal() = Action::LookupOK then begin
                        CustomerLookup.GetRecord(Customer);
                        Rec.SetRange("Customer No.", Customer."No.");
                        CurrPage.SetTableView(Rec);
                        CurrPage.Update(false);
                    end;
                end;
            }

            action(ClearFilters)
            {
                ApplicationArea = All;
                Caption = 'Clear All Filters';
                Image = ClearFilter;
                Promoted = true;
                PromotedCategory = Process;

                trigger OnAction()
                begin
                    Rec.Reset();
                    CurrPage.SetTableView(Rec);
                    CurrPage.Update(false);
                end;
            }
        }
    }

    trigger OnOpenPage();
    var
        RequiredWorkDate: Date;
    begin
        RequiredWorkDate := 20231115D;

        //if WorkDate <> RequiredWorkDate then
        //    Message('Please change your WorkDate to %1', RequiredWorkDate);

    end;
}