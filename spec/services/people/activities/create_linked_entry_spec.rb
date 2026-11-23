# frozen_string_literal: true

require "rails_helper"

RSpec.describe People::Activities::CreateLinkedEntry do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:admin) { create(:user, :admin, customer: customer) }
  let(:user) { create(:user, :member, customer: customer) }
  let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
  let(:entity) do
    enable_module!("authentication", customer).set_extendable_model!(person_model, true)
    create(:entity, customer: customer, name: "Student", extended_model: person_model, property_schema: [
      { name: "Student number", name_slug: "student_number", html_type: "text", validators: [{ type: "presence" }] }
    ].to_json)
  end
  let(:params) { { "student_number" => "S-100" } }
  let(:entries) { EntityEntry.where(customer_id: customer.id, entity_id: entity.id) }

  def run(actor: admin, account: user, target: entity, data: params)
    signal, ctx = described_class.call(customer: customer, actor: actor, user: account, entity: target, params: data)
    [signal.to_h[:semantic], ctx]
  end

  it "creates the entry and links it to the user" do
    semantic, ctx = run

    entry = entries.sole
    expect(semantic).to eq(:success)
    expect(ctx[:model].id).to eq(entry.id)
    expect(entry.user_id).to eq(user.id)
    expect(entry.data_json).to include("student_number" => "S-100")
  end

  it "returns the form with field errors and creates nothing when the entry is invalid" do
    semantic, ctx = run(data: { "student_number" => "" })

    expect(semantic).to eq(:failure)
    expect(ctx[:form].errors_for("student_number")).not_to be_empty
    expect(entries).to be_empty
  end

  it "rolls the new entry back when the link is refused" do
    user.update!(status: :inactive)

    semantic, ctx = run

    expect(semantic).to eq(:failure)
    expect(ctx[:form].errors_for("base")).to eq([I18n.t("people.errors.user_unavailable")])
    expect(ctx[:form].value_for("student_number")).to eq("S-100")
    expect(entries).to be_empty
  end

  it "ends on already_linked without writing when the user already has an entry of the entity" do
    existing = create(:entity_entry, customer: customer, entity: entity, user: user, data: { student_number: "S-1" }.to_json)

    semantic, = run

    expect(semantic).to eq(:already_linked)
    expect(entries).to eq([existing])
  end

  it "forbids members, other tenants' admins, other tenants' users, and non-person entities" do
    foreign = create(:customer)
    cases = [
      { actor: create(:user, :member, customer: customer) },
      { actor: create(:user, :admin, customer: foreign) },
      { account: create(:user, :member, customer: foreign) },
      { target: create(:entity, customer: customer, name: "Course") }
    ]

    cases.each do |overrides|
      semantic, = run(**overrides)
      expect(semantic).to eq(:forbidden), overrides.keys.inspect
    end
    expect(EntityEntry.where(customer_id: [customer.id, foreign.id])).to be_empty
  end

  it "lets the platform owner create and link inside another tenant" do
    semantic, = run(actor: find_or_create_platform_owner)

    expect(semantic).to eq(:success)
    expect(entries.sole.user_id).to eq(user.id)
  end
end
