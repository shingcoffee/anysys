# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::Prompt::Composer do
  let_it_be(:customer) { create(:customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer) }

  def context(mode: :entity)
    AiAssistant::Assistant::Prompt::Context.new(conversation: conversation.reload, mode: mode)
  end

  def prompt(mode: :entity)
    described_class.call(context: context(mode: mode))
  end

  # EntityFocus, PendingProposal and Mentions drop themselves when they have
  # nothing to show; the five website sections drop out while the Website
  # module is off, and the flowchart hand-off is for the platform owner only.
  it "renders every section of the declared outline" do
    expect(described_class::OUTLINES[:entity].size).to eq(19)
    expect(prompt.scan(/^## /).size).to eq(10)

    conversation.update!(user: find_or_create_platform_owner)

    expect(prompt.scan(/^## /).size).to eq(11)
  end

  it "teaches every admin that a greeting builds nothing" do
    expect(prompt).to include("A greeting, thanks or small talk gets a short `chat`")
  end

  it "teaches page processing after the entity examples, then background builds, and leaves journeys to the build" do
    entity = described_class::OUTLINES[:entity]
    sections = AiAssistant::Assistant::Prompt::Sections

    expect(entity.index(sections::PageProcessing)).to eq(entity.index(sections::EntityExamples) + 1)
    expect(entity.index(sections::SubsystemBuilds)).to eq(entity.index(sections::PageProcessing) + 1)
    expect(prompt).not_to include("## Building journeys", "list_journey_options", "generate_journeys")
  end

  it "teaches page processing and background builds to tenant admins and the platform owner" do
    expect(prompt).to include("## What happens when a form is submitted", "## Finishing a sub-system in the background")

    conversation.update!(user: find_or_create_platform_owner)

    expect(prompt).to include("## What happens when a form is submitted", "## Finishing a sub-system in the background")
  end

  it "places clarifying after operation tools and the pending proposal after entity focus" do
    entity = described_class::OUTLINES[:entity]
    sections = AiAssistant::Assistant::Prompt::Sections

    expect(entity.index(sections::Clarifying)).to eq(entity.index(sections::OperationTools) + 1)
    expect(entity.index(sections::PendingProposal)).to eq(entity.index(sections::EntityFocus) + 1)
    expect(described_class::OUTLINES[:flowchart]).not_to include(sections::Clarifying, sections::PendingProposal)
  end

  it "adds the website sections once the Website module is on" do
    enable_module!("website", customer)

    expect(prompt.scan(/^## (.+)$/).flatten).to include(
      "Website section kit (authoritative, generated from the live registries)",
      "Website output contract",
      "How to build website pages",
      "This workspace's website"
    )
    expect(prompt(mode: :flowchart)).not_to include("Website output contract")
  end

  it "rejects a mode with no outline" do
    expect { described_class.call(context: context(mode: :flowchart).tap { |c| c.instance_variable_set(:@mode, :nope) }) }
      .to raise_error(ArgumentError, /unsupported prompt mode/)
  end

  describe "the worked examples" do
    # The few-shots are the strongest signal the model has, so a drift between
    # them and the contract they illustrate is a silent quality regression.
    let(:examples) do
      AiAssistant::Assistant::Prompt::Document
        .read("entity_examples")
        .scan(/```json\n(.*?)\n```/m)
        .flatten
        .map { |raw| JSON.parse(raw) }
    end
    let(:ops_context) do
      Operations::Context.new(customer: customer, actor: conversation.user, channel: "assistant")
    end

    it "are all valid tool calls or final envelopes" do
      enable_module!("authentication", customer, name: "Authentication")
        .set_extendable_model!(EntityDefinitions::Capabilities::PERSON_MODEL, true)
      expect(examples).not_to be_empty

      examples.each do |example|
        if example["tool"].present?
          operation = Operations.for(example["tool"])
          violations, = operation.input_schema(ops_context).validate(example["arguments"])
          expect(violations).to be_empty, "example #{example["tool"]}: #{violations.map(&:as_json)}"
        else
          envelope = AiAssistant::Assistant::ReplyEnvelope.parse(example.to_json)
          expect(envelope).to be_valid, "example #{example["reply"]&.truncate(40)}"
        end
      end
    end

    it "demonstrate a rich, grouped create rather than a bare field list" do
      create = examples.find { |row| row["tool"] == "create_entity" && row.dig("arguments", "entities", 0, "name") == "Student" }
      entity = create.dig("arguments", "entities").first

      expect(entity["attributes"].size).to be >= 10
      expect(entity["attribute_groups"].size).to be >= 3
      expect(entity["attributes"]).to all(include("group"))
    end

    it "demonstrate choice lists on every selection control" do
      selections = examples.select { |row| row["tool"] == "create_entity" }
                           .flat_map { |row| Array(row.dig("arguments", "entities")) }
                           .flat_map { |entity| Array(entity["attributes"]) }
                           .select { |attr| EntityDefinitions::Capabilities.selection_control_values.include?(attr["html_type"]) }

      expect(selections).not_to be_empty
      expect(selections).to all(satisfy { |attr| attr.dig("options", "source").present? })
    end

    it "demonstrate a multi-entity build bridged with per-link attributes" do
      bridged = examples.find { |row|
        Array(row.dig("arguments", "entities")).any? { |entity| entity["associations"].present? }
      }
      association = bridged.dig("arguments", "entities").first.fetch("associations").first

      expect(association["related_entity"]).to be_present
      expect(association["bridge_attributes"]).to be_present
    end

    it "demonstrate proposing a change with update_entity" do
      proposals = examples.select { |row| row["tool"] == "update_entity" }

      expect(proposals).not_to be_empty
    end

    it "never demonstrate the model confirming its own update" do
      expect(examples).to all(satisfy { |row| !row.key?("updates_confirmed") })
    end

    it "never word a proposed change as already done" do
      expect(examples).to all(satisfy { |row| !row["reply"].to_s.start_with?("Added ", "Updated ") })
    end

    it "never extend User before the admin has said these people sign in" do
      document = AiAssistant::Assistant::Prompt::Document.read("entity_examples")
      extending = document.to_enum(:scan, /```json\n(.*?)\n```/m).map { Regexp.last_match }.select do |match|
        Array(JSON.parse(match[1]).dig("arguments", "entities")).any? { |entity| entity["extends"] == EntityDefinitions::Capabilities::PERSON_MODEL }
      end

      expect(extending).not_to be_empty
      extending.each { |match| expect(document[0...match.begin(0)].split(/^\*\*/).last).to match(/sign in/i) }
    end

    it "demonstrate asking whether people sign in, with not signing in pre-selected" do
      question = examples.select { |row| row["intent"] == "clarify" }.flat_map { |row| row["questions"] }
                         .find { |row| row["prompt"].match?(/sign in/i) }

      expect(question).to include("type" => "single")
      expect(question["default"]).to eq(question["options"].find { |option| option.start_with?("No") })
    end

    it "demonstrate creating the domain before its entities, and leave journeys to the sub-system build" do
      tools = examples.filter_map { |row| row["tool"] }

      expect(tools.first(2)).to eq(%w[create_domain create_entity])
      expect(tools).to all(be_in(%w[create_domain create_entity update_entity]))
    end
  end

  describe "the capability matrix" do
    it "lists every control, validator, group icon and colour the app supports" do
      content = prompt

      EntityDefinitions::Capabilities.control_values.each { |value| expect(content).to include(value) }
      EntityDefinitions::Capabilities.validator_types.each { |value| expect(content).to include(value) }
      EntityDefinitions::Capabilities.group_icons.each { |value| expect(content).to include("`#{value}`") }
      EntityDefinitions::Capabilities.group_colors.each { |value| expect(content).to include("`#{value}`") }
    end

    it "tells the model not to set extends when the tenant has no extendable models" do
      expect(prompt).to include("never set `extends`")
    end

    it "lists the tenant's extendable models when it has them" do
      allow(EntityDefinitions::Capabilities)
        .to receive(:extendable_models).with(customer.id).and_return(["Authentication::User"])

      expect(prompt).to include("`Authentication::User`")
    end

    it "names the person base model and the fields an extension inherits" do
      allow(EntityDefinitions::Capabilities)
        .to receive(:extendable_models).with(customer.id).and_return(["Authentication::User"])
      allow(EntityDefinitions::Capabilities)
        .to receive(:base_model_fields).with(customer.id, "Authentication::User")
        .and_return(%w[first_name email])

      content = prompt

      expect(content).to include("Person base model: `Authentication::User`")
      expect(content).to include("only once the admin confirms they sign in")
      expect(content).to include("`Authentication::User` already holds")
      expect(content).to include("`first_name`", "`email`")
    end

    it "says there is no person base model when the tenant cannot extend User" do
      allow(EntityDefinitions::Capabilities)
        .to receive(:extendable_models).with(customer.id).and_return(["Payments::Order"])

      expect(prompt).to include("Person base model: none for this tenant")
    end
  end

  describe "flowchart catalog" do
    it "lists live customer-owned flowcharts in flowchart mode for the platform owner" do
      conversation.update!(user: find_or_create_platform_owner)
      create(:flowchart, customer: customer, name: "Create Student", description: "Builds a student")
      create(:flowchart, customer: create(:customer), name: "Other Tenant Flow")

      content = prompt(mode: :flowchart)

      expect(content).to include("This workspace's flowcharts")
      expect(content).to include("Create Student")
      expect(content).to include("Builds a student")
      expect(content).not_to include("Other Tenant Flow")
      expect(content).not_to include('"entity_name"')
      expect(content).not_to include('"crud_type"')
    end

    it "omits the flowchart catalog when the actor is not the platform owner" do
      create(:flowchart, customer: customer, name: "Create Student")

      expect(prompt(mode: :flowchart)).not_to include("This workspace's flowcharts")
    end
  end

  describe "the entity catalog" do
    it "lists this tenant's domains and the entities placed in each" do
      academics = create(:entity_domain, customer: customer, name: "Academics", color: "blue")
      course = create(:entity, customer: customer, name: "Course")
      EntityDomains::Memberships.place!(course, academics)

      content = prompt

      expect(content).to include("This workspace's entities")
      expect(content).to include("create_domain")
      expect(content).to include("Academics")
      expect(content).to include("\"entities\":[\"Course\"]")
    end
  end

  describe "operation tools" do
    it "lists projected schemas when the vendor has no native tools" do
      content = prompt

      expect(content).to include("Operation tools")
      expect(content).to include(%({"tool": "<name>", "arguments": { ... }}))
      expect(content).to include("`create_domain`")
      expect(content).to include("`create_entity`")
      expect(content).to include("`update_entity`")
      expect(content).to include("`get_entity`")
    end

    it "omits the JSON convention when the vendor supports native tools" do
      create(:ai_assistant_provider_settings)

      content = prompt

      expect(content).to include("Operation tools")
      expect(content).not_to include(%({"tool": "<name>", "arguments": { ... }}))
    end
  end

  it "is identical in every locale, because the prompt is a contract and not user copy" do
    enable_module!("website", customer)
    english = I18n.with_locale(:en) { prompt }
    chinese = I18n.with_locale(:"zh-CN") { prompt }

    expect(chinese).to eq(english)
  end
end
