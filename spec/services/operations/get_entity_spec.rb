# frozen_string_literal: true

require "rails_helper"

RSpec.describe Operations::GetEntity do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other) { create(:customer) }
  let_it_be(:admin) { create(:user, :admin, customer: customer) }
  let_it_be(:foreign_admin) { create(:user, :admin, customer: other) }
  let_it_be(:domain) { create(:entity_domain, customer: customer, name: "Academics") }
  let(:context) { Operations::Context.new(customer: customer, actor: admin, channel: "assistant") }

  def run(name, ctx: context)
    Operations::Activities::Execute.call(operation: "get_entity", input: { "entity" => name }, context: ctx)
  end

  it "returns the public document for a customer-owned entity and does not audit" do
    create(:entity, customer: customer, name: "Course",
           property_schema: [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" }].to_json)
    Operations::Activities::Execute.call(
      operation: "create_entity",
      input: {
        "domain" => domain.name,
        "entities" => [{
          "name" => "Student",
          "attributes" => [{ "name" => "Email", "html_type" => "email" }],
          "associations" => [{ "related_entity" => "Course", "display_field" => "title" }]
        }]
      },
      context: context
    )

    outcome = run("Student")
    expect(outcome.status).to eq("succeeded")
    expect(outcome.data["entity"]).to include("name" => "Student")
    expect(outcome.data["entity"]).not_to have_key("slug")
    expect(outcome.data["entity"]["associations"].first).to include("related_entity" => "Course", "bridge_entity" => "assoc_student_course")
    expect(OperationInvocation.where(operation: "get_entity")).to be_empty
  end

  it "returns not_found for another tenant's entity and for missing names, with candidates" do
    create(:entity, customer: customer, name: "Student")
    create(:entity, customer: other, name: "Foreign")

    missing = run("Studnt")
    expect(missing.status).to eq("invalid")
    expect(missing.violations.first.code).to eq("entity.not_found")
    expect(missing.violations.first.details["candidates"]).to include("Student")
    expect(missing.violations.first.resolution).to eq("fix_payload")

    foreign = run("Foreign")
    expect(foreign.violations.first.code).to eq("entity.not_found")
    expect(foreign.violations.first.resolution).to eq("ask_user")
  end

  it "blocks shared and bridge entities and reports trash" do
    create(:entity, :shared, name: "Catalog")
    create(:entity, customer: customer, name: "assoc_x", category: :bridge)
    create(:entity, customer: customer, name: "Old").tap(&:soft_delete)

    expect(run("Catalog").violations.first.code).to eq("entity.not_editable")
    expect(run("assoc_x").violations.first.code).to eq("entity.not_editable")
    expect(run("Old").violations.first.code).to eq("entity.name_in_trash")
    expect(run("Catalog").violations.first.resolution).to eq("blocked")
  end

  it "forbids an admin of another customer" do
    create(:entity, customer: customer, name: "Student")
    ctx = Operations::Context.new(customer: customer, actor: foreign_admin, channel: "assistant")
    expect(run("Student", ctx: ctx).status).to eq("forbidden")
  end
end
