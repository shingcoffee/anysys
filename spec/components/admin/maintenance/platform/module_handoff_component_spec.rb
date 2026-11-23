# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::ModuleHandoffComponent, type: :component do
  let_it_be(:customer) { create(:customer) }

  def feature_module(key, name)
    find_or_create_feature_module!(key, name: name)
  end

  before { Current.customer = customer }
  after  { Current.customer = nil }

  def render_handoff = render_inline(described_class.new(feature_module: fm))

  context "a module that declares an input contract (payment)" do
    let(:fm) { feature_module("payment", "Payments") }

    it "renders the Integration Contract heading and the illustrated entry path" do
      render_handoff
      expect(page).to have_text("Integration Contract")
      expect(page).to have_text("/#{customer.id}/payments/checkout/start")
    end

    it "lists every input-contract field a page must map" do
      render_handoff
      FeatureModules::Payment::Registration.input_contract_fields.each do |field|
        expect(page).to have_text(field.name)
      end
    end

    it "distinguishes required from optional inputs" do
      render_handoff
      # amount_cents is presence:true (required); body is optional.
      expect(page).to have_text("Optional") # only the optional badge; header covers "Required"
      expect(page).to have_text("one of: CNY") # enum constraint for currency
    end

    it "renders the output-contract fields the module returns" do
      render_handoff
      expect(page).to have_text("payment_reference")
      expect(page).to have_text("Output Fields")
    end
  end

  context "a module with no contract (captcha)" do
    let(:fm) { feature_module("captcha", "Captcha") }

    it "still shows entry/exit but renders an empty state for inputs and outputs" do
      render_handoff
      expect(page).to have_text("Integration Contract")
      expect(page).to have_text("there are no fields to map")
      expect(page).to have_text("no structured output")
    end
  end

  context "when Current.customer is absent" do
    let(:fm) { feature_module("payment", "Payments") }

    it "renders without raising and shows 'Not declared' for the entry path" do
      Current.customer = nil
      expect { render_handoff }.not_to raise_error
      expect(page).to have_text("Not declared")
    end
  end
end
