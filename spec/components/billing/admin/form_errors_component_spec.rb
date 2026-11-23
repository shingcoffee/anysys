# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::FormErrorsComponent, type: :component do
  let(:form) { Billing::Contracts::Plan.new(Billing::Plan.new) }

  it "links real Reform errors to their fields and supplies a persistent alert" do
    form.errors.add(:amount_usd, :not_a_number)
    render_inline described_class.new(errors: form.errors, scope: "billing_plan", label_prefix: "comp_billing.plan_form.fields")
    expect(page).to have_css('[role="alert"]')
    expect(page).to have_link(href: "#billing_plan_amount_usd", text: /Price \(USD\)/)
    expect(page).to have_text(form.errors[:amount_usd].first)
  end

  it "does not render an empty error summary" do
    render_inline described_class.new(errors: form.errors, scope: "billing_plan", label_prefix: "comp_billing.plan_form.fields")
    expect(page).not_to have_css('[role="alert"], ul')
  end
end
