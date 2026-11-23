# frozen_string_literal: true

require "rails_helper"

RSpec.describe People::Activities::Link do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }
  let_it_be(:actor) { create(:user, :admin, customer: customer) }
  let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
  let(:entity) do
    enable_module!("authentication", customer).set_extendable_model!(person_model, true)
    create(:entity, customer: customer, name: "Student", extended_model: person_model,
           property_schema: [{ "name" => "Note", "name_slug" => "note", "type" => "String" }].to_json)
  end
  let(:entry) do
    create(:entity_entry, entity: entity, customer: customer,
           data: { "first_name" => "Ada", "last_name" => "Lovelace", "email" => "ada@example.com", "note" => "kept" }.to_json)
  end
  let(:user) { create(:user, :member, customer: customer, first_name: "Grace", last_name: "Hopper", email: "grace@example.com") }

  def link(record = entry, user_id: user.id, actor: self.actor)
    described_class.call(entry: record, user_id: user_id, actor: actor)
  end

  it "links the user, strips identity keys, keeps other data, and audits" do
    # note is not in the schema — persist must skip entry validation.
    result = link

    expect(result.success?).to be(true)
    expect(result.errors).to eq([])
    expect(result.entry).to eq(entry)
    expect(entry.reload).to have_attributes(user_id: user.id)
    expect(entry).to be_linked
    expect(entry.data_json).to eq("note" => "kept")
    expect(user.reload.roles.map(&:key)).to eq(["member"])

    event = Authentication::Event.where(event: "person.linked").last
    expect(event).to have_attributes(user_id: actor.id, customer_id: customer.id, event: "person.linked")
    expect(event.metadata.stringify_keys).to include(
      "entry_id" => entry.id, "entity_id" => entity.id, "linked_user_id" => user.id
    )
  end

  it "fails when the entity is not a person" do
    plain = create(:entity, customer: customer)
    record = create(:entity_entry, entity: plain, customer: customer)

    result = link(record)
    expect(result.success?).to be(false)
    expect(result.errors).to include(I18n.t("people.errors.not_a_person"))
    expect(record.reload.user_id).to be_nil
  end

  it "fails with one generic message for a missing, other-tenant, or inactive user" do
    foreign = create(:user, customer: other_customer)
    inactive = create(:user, :inactive, customer: customer)
    message = I18n.t("people.errors.user_unavailable")

    [nil, 999_999_999, foreign.id, inactive.id].each do |user_id|
      result = link(user_id: user_id)
      expect(result.success?).to be(false)
      expect(result.errors).to include(message)
    end
    expect(entry.reload.user_id).to be_nil
  end

  it "fails when the entry is already linked" do
    entry.update_columns(user_id: create(:user, customer: customer).id)

    result = link
    expect(result.success?).to be(false)
    expect(result.errors).to include(I18n.t("people.errors.already_linked"))
    expect(entry.reload.user_id).not_to eq(user.id)
  end

  it "fails when the user is already linked to another entry of the same entity" do
    create(:entity_entry, entity: entity, customer: customer, user: user)

    result = link
    expect(result.success?).to be(false)
    expect(result.errors).to include(I18n.t("people.errors.user_already_linked"))
    expect(entry.reload.user_id).to be_nil
  end

  it "does not write an audit row on failure" do
    expect { link(user_id: 999_999_999) }.not_to change { Authentication::Event.where(event: "person.linked").count }
  end

  it "links the same user to entries of two different person entities" do
    entity
    other = create(:entity, customer: customer, name: "Volunteer", extended_model: person_model,
                   property_schema: [{ "name" => "Note", "name_slug" => "note", "type" => "String" }].to_json)
    other_entry = create(:entity_entry, entity: other, customer: customer, data: { "note" => "v" }.to_json)

    expect(link).to be_success
    expect(link(other_entry)).to be_success
    expect(entry.reload.user_id).to eq(user.id)
    expect(other_entry.reload.user_id).to eq(user.id)
  end

  it "returns a failed result when the unique index rejects a concurrent link" do
    create(:entity_entry, entity: entity, customer: customer, user: user)
    allow_any_instance_of(People::Contracts::Link).to receive(:validate).and_return(true)

    result = link
    expect(result.success?).to be(false)
    expect(result.errors).to include(I18n.t("people.errors.user_already_linked"))
    expect(entry.reload.user_id).to be_nil
  end
end
