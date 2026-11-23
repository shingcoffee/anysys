# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Customer invoice print layout", type: :request do
  include_context "as admin"

  let(:subscription) { create(:billing_subscription, customer: customer) }
  let(:invoice) do
    draft = create(:billing_invoice, customer: customer, subscription: subscription, due_at: Time.current)
    72.times do |index|
      create(:billing_invoice_line_item, customer: customer, invoice: draft,
        description: "Print fixture line #{(index + 1).to_s.rjust(3, '0')}", quantity: 1,
        unit_amount_cents: 100, amount_cents: 100)
    end
    Billing::Activities::FinalizeInvoice.call(invoice: draft)
  end

  it "releases the document and shell before the layout emits its opening tags", :settings_print_fixture do
    get download_admin_settings_billing_invoice_path(customer.id, invoice)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    %w[html body].each do |selector|
      expect(document.at_css(selector)["class"]).to include("print:h-auto", "print:overflow-visible")
    end
    ["[data-controller='drawer']", "[data-shell-workspace]", "main"].each do |selector|
      expect(document.at_css(selector)["class"]).to include("print:block", "print:h-auto", "print:overflow-visible")
    end
    expect(document.css("[data-controller='billing-invoice'] tbody tr").length).to eq(72)
    expect(document.at_css("[data-controller='billing-invoice'] tbody tr:last-child").text).to include("Print fixture line 072")
    expect(document.at_css("[data-controller='billing-invoice']").ancestors.none? { |node| node["class"].to_s.split.include?("print:hidden") }).to be(true)
    expect(document.at_css("[data-action='billing-invoice#print']")).to be_present
  end

  it "does not opt the invoice show, index or settings overview into printable mode" do
    [admin_settings_billing_invoice_path(customer.id, invoice),
     admin_settings_billing_invoices_path(customer.id),
     "/#{customer.id}/admin/settings"].each do |path|
      get path
      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      %w[html body main].each do |selector|
        expect(document.at_css(selector)["class"]).not_to include("print:")
      end
      expect(document.at_css("[data-controller='drawer']")["class"]).not_to include("print:")
    end
  end
end
