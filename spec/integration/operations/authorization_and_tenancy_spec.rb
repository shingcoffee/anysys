# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Operations API authorization and tenant isolation" do
  let_it_be(:customer_a) { create(:customer) }
  let_it_be(:customer_b) { create(:customer) }
  let_it_be(:admin_a) { create(:user, :admin, customer: customer_a) }
  let_it_be(:admin_b) { create(:user, :admin, customer: customer_b) }
  let_it_be(:member_a) { create(:user, :member, customer: customer_a) }
  let_it_be(:inactive_a) { create(:user, :admin, :inactive, customer: customer_a) }
  let_it_be(:owner) { find_or_create_platform_owner }

  def context_for(customer, actor, **extra)
    Operations::Context.new(customer: customer, actor: actor, channel: "assistant", **extra)
  end

  def execute(operation, input, ctx)
    Operations::Activities::Execute.call(operation: operation, input: input, context: ctx)
  end

  def confirm(invocation, ctx)
    Operations::Activities::Confirm.call(invocation: invocation, context: ctx)
  end

  def seed_student!(customer, actor)
    domain = EntityDomain.find_by_name(customer.id, "Academics") ||
             create(:entity_domain, customer: customer, name: "Academics")
    execute(
      "create_entity",
      { "domain" => domain.name, "entities" => [{ "name" => "Student", "attributes" => [{ "name" => "Title" }] }] },
      context_for(customer, actor)
    )
    Entity.find_by!(customer_id: customer.id, name: "Student")
  end

  def update_input(name)
    {
      "updates" => [{
        "entity" => name,
        "changes" => [{ "op" => "add_attribute", "attribute" => { "name" => "Notes", "html_type" => "textarea" } }]
      }]
    }
  end

  it "forbids an admin of customer B from executing against customer A's context" do
    outcome = execute(
      "create_entity",
      { "domain" => "Academics", "entities" => [{ "name" => "Secret" }] },
      context_for(customer_a, admin_b)
    )

    expect(outcome.status).to eq("forbidden")
    expect(outcome.violations.first.code).to eq("permission.denied")
    expect(Entity.find_by(customer_id: customer_a.id, name: "Secret")).to be_nil
  end

  it "does not let context customer B read or update customer A's entity" do
    seed_student!(customer_a, admin_a)
    create(:entity, customer: customer_b, name: "Other")

    missing = execute("get_entity", { "entity" => "Student" }, context_for(customer_b, admin_b))
    expect(missing.status).to eq("invalid")
    expect(missing.violations.first.code).to eq("entity.not_found")

    update = execute("update_entity", update_input("Student"), context_for(customer_b, admin_b))
    expect(update.status).to eq("invalid")
    expect(update.violations.first.code).to eq("entity.not_found")
    expect(Entity.find_by!(customer_id: customer_a.id, name: "Student").property_schema_json.map { |row| row["name_slug"] })
      .not_to include("notes")
  end

  it "returns proposal.not_pending when confirming another customer's invocation" do
    seed_student!(customer_a, admin_a)
    parked = execute("update_entity", update_input("Student"), context_for(customer_a, admin_a))
    expect(parked.status).to eq("confirmation_required")

    outcome = confirm(parked.invocation, context_for(customer_b, admin_b))
    expect(outcome.status).to eq("invalid")
    expect(outcome.violations.first.code).to eq("proposal.not_pending")
    expect(parked.invocation.reload).to be_awaiting_confirmation
    expect(Entity.find_by!(customer_id: customer_a.id, name: "Student").property_schema_json.map { |row| row["name_slug"] })
      .not_to include("notes")
  end

  it "forbids members and inactive actors" do
    member = execute(
      "create_entity",
      { "domain" => "Academics", "entities" => [{ "name" => "MemberEntity" }] },
      context_for(customer_a, member_a)
    )
    expect(member.status).to eq("forbidden")

    inactive = execute(
      "get_entity",
      { "entity" => "Student" },
      context_for(customer_a, inactive_a)
    )
    expect(inactive.status).to eq("forbidden")
    expect(Entity.find_by(customer_id: customer_a.id, name: "MemberEntity")).to be_nil
  end

  it "lets the platform owner operate on the platform customer context" do
    platform = owner.customer
    domain = EntityDomain.find_by_name(platform.id, "Academics") ||
             create(:entity_domain, customer: platform, name: "Academics")
    outcome = execute(
      "create_entity",
      { "domain" => domain.name, "entities" => [{ "name" => "OwnerNotebook", "attributes" => [{ "name" => "Title" }] }] },
      context_for(platform, owner)
    )

    expect(outcome.status).to eq("succeeded"), Array(outcome.violations).map(&:as_json).inspect
    expect(Entity.find_by(customer_id: platform.id, name: "OwnerNotebook")).to be_present
  end

  it "forbids a foreign admin through the assistant session for another tenant's context" do
    conversation = create(:ai_assistant_conversation, customer: customer_a, user: admin_b)
    session = AiAssistant::Assistant::Tools::Session.new(
      customer: customer_a,
      viewer: admin_b,
      conversation: conversation
    )

    result = session.call("create_entity", "domain" => "Academics", "entities" => [{ "name" => "CrossTenant" }])
    expect(result).to include("ok" => false, "status" => "forbidden")
    expect(Entity.find_by(customer_id: customer_a.id, name: "CrossTenant")).to be_nil
  end
end
