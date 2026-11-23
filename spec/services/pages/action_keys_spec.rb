# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::ActionKeys do
  let(:customer) { create(:customer) }
  let(:other) { create(:customer) }

  it "returns the base key while it is free" do
    expect(described_class.unique("student_new", customer_id: customer.id)).to eq("student_new")
  end

  it "counts an inactive page of the customer as taken" do
    create(:page, customer: customer, action_key: "student_new").update_columns(status: Page.statuses[:inactive])

    expect(described_class.unique("student_new", customer_id: customer.id)).to eq("student_new_2")
  end

  it "counts a shared page as taken" do
    create(:page, :shared, action_key: "student_new")

    expect(described_class.taken?("student_new", customer_id: customer.id)).to be(true)
  end

  it "ignores another customer's page" do
    create(:page, customer: other, action_key: "student_new")

    expect(described_class.taken?("student_new", customer_id: customer.id)).to be(false)
  end
end
