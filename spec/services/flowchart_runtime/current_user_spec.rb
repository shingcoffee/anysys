# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::CurrentUser do
  let(:customer) { create(:customer) }
  let(:other) { create(:customer) }
  let(:user) { create(:user, :admin, customer: customer, first_name: "Ada", last_name: "Lovelace") }
  let(:foreign) { create(:user, :member, customer: other) }

  it "returns a frozen hash for the tenant user and never another tenant's user" do
    payload = described_class.load(customer_id: customer.id, current_user_id: user.id)

    expect(payload).to be_frozen
    expect(payload).to eq(
      "id" => user.id,
      "email" => user.email,
      "name" => "Ada Lovelace",
      "role" => "admin",
      "person_entries" => {}
    )
    expect(payload).not_to have_key("member_profile_id")
    expect(described_class.load(customer_id: customer.id, current_user_id: foreign.id)).to be_nil
    expect(described_class.load(customer_id: other.id, current_user_id: user.id)).to be_nil
  end

  it "includes person_entries for linked person records in the user's tenant" do
    person_model = EntityDefinitions::Capabilities::PERSON_MODEL
    enable_module!("authentication", customer).set_extendable_model!(person_model, true)
    enable_module!("authentication", other).set_extendable_model!(person_model, true)
    student = create(:entity, customer: customer, name: "Student", extended_model: person_model)
    foreign_student = create(:entity, customer: other, name: "Student", extended_model: person_model)
    entry = create(:entity_entry, entity: student, customer: customer, user: user)
    forged = create(:entity_entry, entity: foreign_student, customer: other).tap do |row|
      row.update_columns(user_id: user.id)
    end

    payload = described_class.load(customer_id: customer.id, current_user_id: user.id)
    expect(payload["person_entries"]).to eq(student.id.to_s => entry.id)
    expect(payload["person_entries"].values).not_to include(forged.id)
    expect(payload).not_to have_key("member_profile_id")
  end

  it "returns nil when the signed-in id is missing" do
    expect(described_class.load(customer_id: customer.id, current_user_id: nil)).to be_nil
    expect(described_class.load(customer_id: nil, current_user_id: user.id)).to be_nil
  end
end
