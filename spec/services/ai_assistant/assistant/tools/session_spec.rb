# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::Tools::Session do
  let(:customer) { create(:customer) }
  let(:admin) { create(:user, :admin, customer: customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: admin) }
  let(:session) { described_class.new(customer: customer, viewer: admin, conversation: conversation) }
  let!(:domain) { create(:entity_domain, customer: customer, name: "Academics") }

  def create_input(name)
    { "domain" => domain.name, "entities" => [{ "name" => name, "attributes" => [{ "name" => "Title" }] }] }
  end

  def update_input(name)
    {
      "updates" => [
        {
          "entity" => name,
          "changes" => [
            { "op" => "add_attribute", "attribute" => { "name" => "Notes", "html_type" => "textarea" } }
          ]
        }
      ]
    }
  end

  it "keeps catalog reads tenant scoped" do
    create(:entity, customer: customer, name: "Mine")
    create(:entity, customer: create(:customer), name: "Theirs")

    result = session.call("list_catalog")
    names = Array(result["entities"]).map { |row| row["name"] || row[:name] }

    expect(names).to include("Mine")
    expect(names).not_to include("Theirs")
    expect(session.effects).to be_empty
  end

  it "offers a tenant admin page processing and builds through tools that never say flowchart" do
    tools = session.native_tools
    definitions = tools.map do |tool|
      { name: tool.name, description: tool.description, schema: tool.respond_to?(:params_schema) ? tool.params_schema : nil }
    end

    expect(tools.map(&:name)).to include("set_page_processing", "start_subsystem_build")
    expect(definitions.to_json).not_to match(/flowchart/i)
  end

  it "lists the workspace's own form processing under a neutral key for every admin" do
    create(:flowchart, customer: customer, name: "Notify registrar", description: "Emails the registrar")
    create(:flowchart, customer: create(:customer), name: "Theirs")

    result = session.call("list_catalog")
    owner_result = described_class.new(customer: customer, viewer: find_or_create_platform_owner).call("list_catalog")

    [result, owner_result].each do |payload|
      expect(payload).not_to have_key("flowcharts")
      expect(payload["processing"].map { |row| row["name"] }).to eq(["Notify registrar"])
    end
    expect(result.to_json).not_to match(/flowchart/i)
  end

  it "lists the workspace's own launched record pages by the key set_page_processing takes" do
    entity = create(:entity, customer: customer, name: "Course")
    create(:page, customer: customer, entity: entity, name: "Add course", action_key: "course_add", launched: true)
    create(:page, customer: customer, entity: entity, name: "Draft course", action_key: "course_draft")
    other = create(:customer)
    create(:page, customer: other, entity: create(:entity, customer: other, name: "Course"), action_key: "theirs", launched: true)

    pages = session.call("list_catalog")["pages"]

    expect(pages).to contain_exactly(include("action_key" => "course_add", "name" => "Add course", "entity" => "Course"))
    expect(pages.first["processing"]).to be_present
  end

  it "does not verify a flowchart unless the viewer is the platform owner" do
    flowchart = create(:flowchart, :simple, customer: customer)

    denied = session.call("verify_artifact", "kind" => "flowchart", "id" => flowchart.id)
    expect(denied["ok"]).to eq(false)

    allowed = described_class.new(
      customer: customer,
      viewer: find_or_create_platform_owner
    ).call("verify_artifact", "kind" => "flowchart", "id" => flowchart.id)
    expect(allowed["ok"]).to eq(true)
  end

  it "verifies a website page only while the Website module is on" do
    website_page = create(
      :website_page,
      website: create(:website, customer: customer),
      sections: [{ "id" => "sec_1", "type" => "rich_text", "props" => { "heading" => "Hi" } }]
    )
    verify = -> { session.call("verify_artifact", "kind" => "website_page", "id" => website_page.id) }

    expect(verify.call["ok"]).to eq(false)

    enable_module!("website", customer)
    expect(verify.call["ok"]).to eq(true)
  end

  it "records a successful page write as an effect" do
    entity = create(:entity, :with_name_status_schema, customer: customer, name: "Student")

    result = session.call("generate_page", "entity_name" => entity.name)

    expect(result["ok"]).to eq(true)
    generated = Page.find(result["page_id"])
    expect(generated).to have_attributes(launched: true)
    expect(generated.visible_audiences).to eq(%w[admin])
    expect(session.effects.map { |effect| effect[:record].id }).to include(result["page_id"])
    expect(session.effects.first[:action]).to eq("created")
  end

  it "records an existing generated page as reused" do
    entity = create(:entity, :with_name_status_schema, customer: customer, name: "Student")
    first = session.call("generate_page", "entity_name" => entity.name)
    page = Page.find(first["page_id"])
    page.launched = false
    page.visible_audiences = %w[admin member]
    page.save!

    result = session.call("generate_page", "entity_name" => entity.name)

    expect(result["ok"]).to eq(true)
    expect(page.reload).to have_attributes(launched: false)
    expect(page.visible_audiences).to eq(%w[admin member])
    expect(session.effects.last).to include(
      kind: "page",
      action: "reused",
      record: Page.find(result["page_id"])
    )
  end

  it "reports a launch failure without recording an effect or a page id" do
    entity = create(:entity, customer: customer, name: "Empty Student")
    result = nil

    expect { result = session.call("generate_page", "entity_name" => entity.name) }
      .not_to change { [Page.with_deleted.count, PageVersion.count] }

    expect(result).to include("ok" => false, "page_id" => nil)
    expect(result["message"]).to include(I18n.t("maint_core.errors.page_launch.no_fields"))
    expect(session.effects).to be_empty
  end

  it "builds native tools backed by the same session" do
    tools = session.native_tools

    expect(tools.map(&:name)).to include(
      "list_catalog",
      "generate_page",
      "verify_artifact",
      "create_domain",
      "create_entity",
      "update_entity",
      "get_entity"
    )
    expect(tools.map { |tool| tool.instance_variable_get(:@session) }.uniq).to eq([session])
  end

  it "refuses a page write after its generation is superseded" do
    entity = create(:entity, :with_name_status_schema, customer: customer, name: "Student")
    user = create(:user, :admin, customer: customer)
    conversation = create(:ai_assistant_conversation, customer: customer, user: user)
    message = create(:ai_assistant_message, customer: customer, conversation: conversation)
    generation = AiAssistant::Assistant::GenerationLifecycle.start!(
      conversation: conversation,
      user_message: message
    )
    AiAssistant::Assistant::GenerationLifecycle.claim!(generation)
    guarded_session = described_class.new(
      customer: customer,
      write_guard: AiAssistant::Assistant::GenerationWriteGuard.new(generation: generation)
    )
    newer_message = create(
      :ai_assistant_message,
      customer: customer,
      conversation: conversation,
      body: "Newer"
    )
    AiAssistant::Assistant::GenerationLifecycle.start!(
      conversation: conversation,
      user_message: newer_message
    )

    result = guarded_session.call("generate_page", "entity_name" => entity.name)

    expect(result["ok"]).to eq(false)
    expect(
      Page.where(customer_id: customer.id, entity_version_id: entity.current_version.id)
    ).to be_empty
    expect(guarded_session.effects).to be_empty
  end

  it "does not turn a page-write database failure into a model-visible error" do
    entity = create(:entity, customer: customer, name: "Student")
    allow(AiAssistant::Assistant::GeneratePage).to receive(:call)
      .with(entity: entity, customer: customer)
      .and_raise(ActiveRecord::StatementInvalid, "database unavailable")

    expect {
      session.call("generate_page", "entity_name" => entity.name)
    }.to raise_error(ActiveRecord::StatementInvalid, "database unavailable")
  end

  it "dispatches create_domain through Execute without treating it as an entity write" do
    expect(described_class::ENTITY_OPERATIONS).not_to include("create_domain")

    result = session.call("create_domain", "name" => "Ticketing", "color" => "teal")

    expect(result).to include("ok" => true, "status" => "succeeded", "operation" => "create_domain")
    expect(result.dig("data", "domain")).to include("name" => "Ticketing", "color" => "teal")
    expect(EntityDomain.find_by_name(customer.id, "Ticketing")).to be_present
    expect(session.effects).to be_empty
    expect(session.pending_proposal).to be_nil
  end

  it "dispatches create_entity through Execute and records the outcome" do
    result = session.call("create_entity", create_input("Student"))

    expect(result).to include("ok" => true, "status" => "succeeded", "operation" => "create_entity")
    expect(result.dig("data", "created").first).to include("name" => "Student")
    expect(Entity.find_by(customer_id: customer.id, name: "Student")).to be_present
    expect(session.operation_outcomes.map(&:status)).to eq(["succeeded"])
    expect(session.effects).to be_empty
    expect(session.pending_proposal).to be_nil
  end

  it "builds an idempotency key from the generation, operation, and input digest" do
    user_message = create(:ai_assistant_message, conversation: conversation, customer: customer)
    generation = AiAssistant::Assistant::GenerationLifecycle.start!(
      conversation: conversation,
      user_message: user_message
    )
    guarded = described_class.new(
      customer: customer,
      viewer: admin,
      conversation: conversation,
      generation: generation
    )
    input = create_input("Cohort")

    first = guarded.call("create_entity", input)
    second = guarded.call("create_entity", input)

    expect(first["status"]).to eq("succeeded")
    expect(second["status"]).to eq("succeeded")
    expect(Entity.where(customer_id: customer.id, name: "Cohort").count).to eq(1)
    key = "gen-#{generation.id}-create_entity-#{Operations::Activities::Execute.input_digest(input)}"
    expect(OperationInvocation.find_by(customer_id: customer.id, idempotency_key: key)).to be_present
  end

  it "rejects a fourth call after three rejected calls to the same operation in one turn" do
    results = Array.new(4) { session.call("get_entity", "entity" => "Missing") }

    expect(results.first(3)).to all(include("status" => "invalid"))
    expect(results.first(3).map { |payload| payload["attempts_remaining"] }).to eq([2, 1, 0])
    expect(results.last).to include("ok" => false, "status" => "invalid")
    expect(results.last["errors"]).to include(hash_including("code" => "attempts.exhausted", "resolution" => "blocked"))
  end

  it "does not spend the retry budget on successful calls" do
    create(:entity, :with_name_status_schema, customer: customer, name: "Student")
    results = Array.new(4) { session.call("get_entity", "entity" => "Student") }

    expect(results).to all(include("ok" => true, "status" => "succeeded"))
    expect(results).to all(satisfy { |payload| !payload.key?("attempts_remaining") })
  end

  it "rejects a second parked proposal without calling Execute" do
    create(:entity, :with_name_status_schema, customer: customer, name: "Student")
    first = session.call("update_entity", update_input("Student"))
    expect(first["status"]).to eq("confirmation_required")
    expect(session.pending_proposal).to include("kind" => "operation", "operation" => "update_entity")

    expect(Operations::Activities::Execute).not_to receive(:call)
    second = session.call("update_entity", update_input("Student").merge(
      "updates" => [
        {
          "entity" => "Student",
          "changes" => [{ "op" => "add_attribute", "attribute" => { "name" => "Phone", "html_type" => "tel" } }]
        }
      ]
    ))

    expect(second).to include("ok" => false, "status" => "invalid")
    expect(second["errors"]).to include(hash_including("code" => "proposal.already_pending"))
    expect(OperationInvocation.awaiting_confirmation.where(customer_id: customer.id).count).to eq(1)
  end

  it "maps a rejected generation write to the existing tool error" do
    user_message = create(:ai_assistant_message, conversation: conversation, customer: customer)
    generation = AiAssistant::Assistant::GenerationLifecycle.start!(
      conversation: conversation,
      user_message: user_message
    )
    AiAssistant::Assistant::GenerationLifecycle.claim!(generation)
    guarded = described_class.new(
      customer: customer,
      viewer: admin,
      conversation: conversation,
      generation: generation,
      write_guard: AiAssistant::Assistant::GenerationWriteGuard.new(generation: generation)
    )
    newer = create(:ai_assistant_message, conversation: conversation, customer: customer, body: "Newer")
    AiAssistant::Assistant::GenerationLifecycle.start!(conversation: conversation, user_message: newer)

    result = guarded.call("create_entity", create_input("StaleEntity"))

    expect(result).to eq(
      "ok" => false,
      "error" => I18n.t("ai_assistant.assistant.tools.generation_not_current")
    )
    expect(Entity.find_by(customer_id: customer.id, name: "StaleEntity")).to be_nil
  end

  it "evaluates tool payloads in the default locale even when the admin locale is zh-CN" do
    payload = nil
    unknown = nil
    I18n.with_locale(:"zh-CN") do
      payload = session.call("get_entity", "entity" => "Missing")
      unknown = session.call("not_a_real_tool")
    end

    expect(payload["next_step"]).to include("Attempts remaining")
    expect(payload["next_step"]).not_to include("剩余尝试次数")
    expect(payload["errors"].first.fetch("message")).to include(
      I18n.t("operations.violations.entity.not_found", name: "Missing", locale: :en)
    )
    expect(payload["errors"].first.fetch("message")).not_to include(
      I18n.t("operations.violations.entity.not_found", name: "Missing", locale: :"zh-CN")
    )
    expect(unknown["error"]).to eq(
      I18n.t("ai_assistant.assistant.tools.unknown", name: "not_a_real_tool", locale: :en)
    )
  end

  it "lists catalog entities in the public vocabulary" do
    create(:entity, :with_name_status_schema, customer: customer, name: "Mine")
    create(:entity, customer: create(:customer), name: "Theirs")

    result = session.call("list_catalog")
    mine = result["entities"].find { |row| row["name"] == "Mine" }

    expect(mine).to include("attributes", "attribute_groups", "version")
    expect(mine.fetch("attributes").map { |attribute| attribute.fetch("slug") }).to include("name", "status")
    expect(mine).not_to have_key("property_schema")
    expect(result["entities"].map { |row| row["name"] }).not_to include("Theirs")
  end
end
