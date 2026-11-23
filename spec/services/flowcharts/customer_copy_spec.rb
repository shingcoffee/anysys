# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flowcharts::CustomerCopy do
  let(:customer) { create(:customer) }
  let(:name) { I18n.t("maint_core.flowcharts.default_page_flowchart.name", locale: I18n.default_locale) }

  def delete_shared(singleton) = singleton.fetch.update_columns(status: Flowchart.statuses[:deleted])
  def steps(flowchart) = flowchart.elements.flat_map { |element| Array(element.dig("properties", "steps")).pluck("action") }

  it "hands out the shared flowchart while it exists" do
    shared = Flowcharts::DefaultPageFlowchart.fetch

    expect { expect(Flowcharts::DefaultPageFlowchart.for_customer(customer)).to eq(shared) }.not_to change(Flowchart.unscoped, :count)
  end

  context "once the platform owner deletes the shared Save page record" do
    before { delete_shared(Flowcharts::DefaultPageFlowchart) }

    it "creates the customer's own launched Save page record on their line and reuses it" do
      copy = Flowcharts::DefaultPageFlowchart.for_customer(customer)

      expect(copy).to have_attributes(customer_id: customer.id, name: name, status: "launched")
      expect(steps(copy)).to eq(%w[build_contract validate_contract save_model])
      expect(copy.current_version).to have_attributes(customer_id: customer.id)
      expect(Flowcharts::DefaultPageFlowchart.for_customer(customer)).to eq(copy)
      expect(Flowcharts::DefaultPageFlowchart.fetch).to be_nil
    end

    it "gives each customer a copy of their own" do
      other = create(:customer)

      copies = [customer, other].map { |owner| Flowcharts::DefaultPageFlowchart.for_customer(owner) }

      expect(copies.map(&:customer_id)).to eq([customer.id, other.id])
      expect(copies.map(&:uuid).uniq.size).to eq(2)
    end

    it "brings a trashed copy back launched" do
      copy = Flowcharts::DefaultPageFlowchart.for_customer(customer)
      copy.soft_delete

      expect { expect(Flowcharts::DefaultPageFlowchart.for_customer(customer)).to eq(copy) }.not_to change(Flowchart.unscoped, :count)
      expect(copy.reload).to be_launched
    end

    it "leaves a copy the platform owner took offline offline" do
      copy = Flowcharts::DefaultPageFlowchart.for_customer(customer)
      copy.update!(status: :draft)

      expect(Flowcharts::DefaultPageFlowchart.for_customer(customer)).to eq(copy)
      expect(copy.reload).to be_draft
    end

    it "is nil when the customer has another flowchart by that name" do
      create(:flowchart, :simple, customer: customer, name: name)

      expect(Flowcharts::DefaultPageFlowchart.for_customer(customer)).to be_nil
    end
  end

  it "copies the sign-up flowchart once the shared one is deleted" do
    delete_shared(Flowcharts::SignUpPageFlowchart)

    copy = Flowcharts::SignUpPageFlowchart.for_customer(customer)

    expect(copy).to have_attributes(customer_id: customer.id, status: "launched",
                                    name: I18n.t("maint_core.flowcharts.sign_up_page_flowchart.name", locale: I18n.default_locale))
    expect(steps(copy)).to eq(%w[build_contract validate_contract register_member save_model])
    expect(copy).not_to eq(Flowcharts::DefaultPageFlowchart.for_customer(customer))
  end
end
