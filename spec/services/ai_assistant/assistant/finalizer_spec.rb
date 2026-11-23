# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::Finalizer do
  let(:customer) { create(:customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer) }

  it "builds change metadata and selects the tenant artifact" do
    entity = create(:entity, customer: customer, name: "Student")
    entity_result = AiAssistant::Assistant::TurnProcessor::EntityTurn.new(
      body: "Created Student.",
      status: "complete",
      applied: true,
      created: ["Student"],
      updated: [],
      bridges: []
    )
    turn = AiAssistant::Assistant::TurnProcessor::Result.new(
      body: "Created Student.",
      status: "complete",
      entity_result: entity_result
    )

    result = described_class.call(turn: turn, conversation: conversation)

    expect(result.status).to eq("complete")
    expect(result.metadata.fetch("changes")).to include(
      "kind" => "entity",
      "action" => "created",
      "name" => "Student"
    )
    expect(result.artifact).to eq(entity)
    expect(result.artifact_kind).to eq("entity")
  end

  it "generates, launches, and pins the admin form for an applied entity turn" do
    entity = create(:entity, :with_name_status_schema, customer: customer, name: "Student")
    turn = AiAssistant::Assistant::TurnProcessor::Result.new(
      body: "Created Student.", status: "complete",
      entity_result: AiAssistant::Assistant::TurnProcessor::EntityTurn.new(
        applied: true, created: [entity.name], updated: [], bridges: []
      )
    )

    result = described_class.call(turn: turn, conversation: conversation)

    page = Page.find_by!(customer_id: customer.id, entity_version_id: entity.current_version_id)
    expect(page).to have_attributes(launched: true)
    expect(page.visible_audiences).to eq(%w[admin])
    expect(result).to have_attributes(artifact: page, artifact_kind: "page", status: "complete")
    expect(result.body).to include(I18n.t("ai_assistant.assistant.apply_page_created", names: page.name))
    expect(result.metadata.fetch("changes")).to include(
      { "kind" => "entity", "action" => "created", "name" => entity.name },
      { "kind" => "page", "action" => "created", "name" => page.name }
    )
  end

  describe "generated form links" do
    def applied_turn(*names, effects: [])
      AiAssistant::Assistant::TurnProcessor::Result.new(
        body: "Built it.", status: "complete", effects: effects,
        entity_result: AiAssistant::Assistant::TurnProcessor::EntityTurn.new(
          applied: names.any?, created: names, updated: [], bridges: []
        )
      )
    end

    def form_for(entity)
      Page.find_by!(customer_id: customer.id, entity_version_id: entity.reload.current_version_id)
    end

    def associate(source, target)
      source.update!(associations: [
        { "target_entity_id" => target.id, "display_field" => "name", "display_field_label" => "Name" }
      ].to_json)
    end

    it "links only the primary entity's form when its associated entity's form was generated too" do
      student = create(:entity, :with_name_status_schema, customer: customer, name: "Student")
      course = create(:entity, :with_name_status_schema, customer: customer, name: "Course")
      associate(course, student)

      result = described_class.call(turn: applied_turn("Student", "Course"), conversation: conversation)

      expect(form_for(student)).to be_launched
      course_form = form_for(course)
      expect(result.metadata.fetch("page_links")).to eq([{ "id" => course_form.id, "name" => course_form.name }])
    end

    it "links every form when the generated entities are unrelated" do
      student = create(:entity, :with_name_status_schema, customer: customer, name: "Student")
      teacher = create(:entity, :with_name_status_schema, customer: customer, name: "Teacher")

      result = described_class.call(turn: applied_turn("Student", "Teacher"), conversation: conversation)

      expect(result.metadata.fetch("page_links").map { |link| link["id"] })
        .to eq([form_for(student).id, form_for(teacher).id])
    end

    it "links the associated entity's form when it is the only form the turn produced" do
      student = create(:entity, :with_name_status_schema, customer: customer, name: "Student")
      course = create(:entity, :with_name_status_schema, customer: customer, name: "Course")
      associate(course, student)

      result = described_class.call(turn: applied_turn("Student"), conversation: conversation)

      expect(result.metadata.fetch("page_links").map { |link| link["id"] }).to eq([form_for(student).id])
    end

    it "links a form the generate_page tool produced during the turn once" do
      student = create(:entity, :with_name_status_schema, customer: customer, name: "Student")
      tool_form = AiAssistant::Assistant::GeneratePage.call(entity: student, customer: customer).page
      effects = [{ kind: "page", action: "created", record: tool_form }]

      result = described_class.call(turn: applied_turn("Student", effects: effects), conversation: conversation)

      expect(result.metadata.fetch("page_links")).to eq([{ "id" => tool_form.id, "name" => tool_form.name }])
    end

    it "omits a reused form that is offline and a page record from another tenant" do
      student = create(:entity, :with_name_status_schema, customer: customer, name: "Student")
      offline = AiAssistant::Assistant::GeneratePage.call(entity: student, customer: customer).page
      offline.update!(launched: false)
      foreign = create(:page, customer: create(:customer), launched: true)
      effects = [{ kind: "page", action: "reused", record: foreign }]

      result = described_class.call(turn: applied_turn("Student", effects: effects), conversation: conversation)

      expect(result.metadata).not_to have_key("page_links")
    end

    it "sets the platform notes apart from the reply prose" do
      student = create(:entity, :with_name_status_schema, customer: customer, name: "Student")

      result = described_class.call(turn: applied_turn("Student"), conversation: conversation)

      expect(result.body).to eq(
        "Built it.\n\n- #{I18n.t('ai_assistant.assistant.apply_page_created', names: form_for(student).name)}"
      )
    end
  end

  it "pins the last website page and records website changes" do
    website = create(:website, customer: customer)
    sections = [{ "id" => "sec_1", "type" => "rich_text", "props" => { "heading" => "Hi" } }]
    home = create(:website_page, :home, website: website, sections: sections)
    about = create(:website_page, website: website, title: "About", sections: sections)
    website_result = Websites::Assistant::Processor::Message.new(
      body: "Built your site.",
      status: "complete",
      intent: "apply_website",
      applied: true,
      created: ["About"],
      updated: ["Home"],
      pages: [home, about]
    )
    turn = AiAssistant::Assistant::TurnProcessor::Result.new(
      body: "Built your site.",
      status: "complete",
      website_result: website_result
    )

    result = described_class.call(turn: turn, conversation: conversation)

    expect(result.artifact).to eq(about)
    expect(result.artifact_kind).to eq("website_page")
    expect(result.body).to eq("Built your site.")
    expect(result.metadata.fetch("changes")).to contain_exactly(
      { "kind" => "website_page", "action" => "created", "name" => "About" },
      { "kind" => "website_page", "action" => "updated", "name" => "Home" }
    )
    expect(result.metadata).not_to have_key(Websites::Assistant::Undo::KEY)
  end

  it "pins the first page that shows the site's own photos instead of a later text-only page" do
    website = create(:website, customer: customer)
    intro = create(:website_page, :home, website: website, sections: [
      { "type" => "hero_centered", "props" => { "image_url" => "https://images.unsplash.com/photo-1" } }
    ])
    gallery = create(:website_page, website: website, title: "Available Pets", sections: [
      { "type" => "card_grid", "props" => { "cards" => [{ "image_url" => "/#{customer.id}/site/media/dog" }] } }
    ])
    adopt = create(:website_page, website: website, title: "Adopt", sections: [
      { "type" => "statement", "props" => { "headline" => "Adopt" } }
    ])
    website_result = Websites::Assistant::Processor::Message.new(
      body: "Built.", status: "complete", intent: "apply_website", applied: true,
      created: ["Home", "Available Pets", "Adopt"], updated: [], pages: [intro, gallery, adopt]
    )
    turn = AiAssistant::Assistant::TurnProcessor::Result.new(body: "Built.", status: "complete", website_result: website_result)

    expect(described_class.call(turn: turn, conversation: conversation).artifact).to eq(gallery)
  end

  it "stores the undo entries of an applied website document on the reply" do
    entries = [{ "page_id" => 1, "title" => "About", "created" => true, "fingerprint" => "abc" }]
    website_result = Websites::Assistant::Processor::Message.new(
      body: "Built.", status: "complete", intent: "apply_website", applied: true,
      created: ["About"], updated: [], pages: [], undo: entries
    )
    turn = AiAssistant::Assistant::TurnProcessor::Result.new(body: "Built.", status: "complete", website_result: website_result)

    result = described_class.call(turn: turn, conversation: conversation)

    expect(result.metadata.fetch(Websites::Assistant::Undo::KEY)).to eq("pages" => entries)
  end

  it "neither pins nor records a website document that was not applied" do
    website_result = Websites::Assistant::Processor::Message.new(
      body: "Could not build it.",
      status: "complete",
      intent: "apply_website",
      applied: false,
      created: [],
      updated: [],
      pages: []
    )
    turn = AiAssistant::Assistant::TurnProcessor::Result.new(
      body: "Could not build it.",
      status: "complete",
      website_result: website_result
    )

    result = described_class.call(turn: turn, conversation: conversation)

    expect(result.artifact).to be_nil
    expect(result.metadata.fetch("changes")).to eq([])
  end

  it "writes questions and assumptions onto complete-turn metadata when they are present" do
    questions = AiAssistant::Assistant::Questions.sanitize([
      { "prompt" => "Which stages?", "type" => "multiple", "options" => %w[A B], "default" => %w[A] }
    ])
    turn = AiAssistant::Assistant::TurnProcessor::Result.new(
      body: "Two lists are specific to your team.",
      status: "complete",
      questions: questions,
      assumptions: ["Amount is in your reporting currency."]
    )

    result = described_class.call(turn: turn, conversation: conversation)

    expect(result.metadata["questions"]).to eq(questions)
    expect(result.metadata["assumptions"]).to eq(["Amount is in your reporting currency."])
  end

  it "omits questions and assumptions unless the turn completed with a non-empty list" do
    failed = described_class.call(
      turn: AiAssistant::Assistant::TurnProcessor::Result.new(
        body: I18n.t("ai_assistant.assistant.reply_failed"),
        status: "failed",
        questions: [{ "prompt" => "Which stages?" }],
        assumptions: ["Should not persist."]
      ),
      conversation: conversation
    )
    empty = described_class.call(
      turn: AiAssistant::Assistant::TurnProcessor::Result.new(
        body: "Hello.",
        status: "complete",
        questions: [],
        assumptions: []
      ),
      conversation: conversation
    )
    unset = described_class.call(
      turn: AiAssistant::Assistant::TurnProcessor::Result.new(
        body: I18n.t("ai_assistant.assistant.reply_failed"),
        status: "failed"
      ),
      conversation: conversation
    )

    expect(failed.metadata).not_to have_key("questions")
    expect(failed.metadata).not_to have_key("assumptions")
    expect(empty.metadata).not_to have_key("questions")
    expect(empty.metadata).not_to have_key("assumptions")
    expect(unset.metadata).not_to have_key("questions")
    expect(unset.metadata).not_to have_key("assumptions")
  end

  it "retains and verifies a tool-created artifact when the turn later fails" do
    page = create(:page, customer: customer)
    turn = AiAssistant::Assistant::TurnProcessor::Result.new(
      body: I18n.t("ai_assistant.assistant.reply_failed"),
      status: "failed",
      effects: [{ kind: "page", action: "created", record: page }]
    )
    allow(AiAssistant::Assistant::Verify).to receive(:call)
      .with(kind: "page", record: page, customer: customer)
      .and_return(AiAssistant::Assistant::Verify::Result.new(ok: true, issues: []))

    result = described_class.call(turn: turn, conversation: conversation)

    expect(result.artifact).to eq(page)
    expect(result.artifact_kind).to eq("page")
    expect(result.metadata.fetch("changes")).to include(
      "kind" => "page",
      "action" => "created",
      "name" => page.name
    )
  end
end
