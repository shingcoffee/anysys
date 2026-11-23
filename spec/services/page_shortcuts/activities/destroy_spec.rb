# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageShortcuts::Activities::Destroy do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }
  let(:page) { create(:page, customer: customer) }
  let(:shortcut) { PageShortcut.create!(customer_id: customer.id, path: "/join", target: page) }

  it "scopes deletes and removes unavailable mappings without deleting the destination" do
    expect(described_class.call(shortcut: shortcut, customer_id: other_customer.id).success?).to be(false)
    expect(shortcut.reload).to be_persisted
    result = nil
    expect { result = described_class.call(shortcut: shortcut, customer_id: customer.id) }.not_to change(Page, :count)
    expect(result.success?).to be(true)
    expect(result.errors).to eq({})
    expect(shortcut).to be_destroyed
  end
end
