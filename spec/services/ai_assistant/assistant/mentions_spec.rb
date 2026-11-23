# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::Mentions do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other) { create(:customer) }

  def resolve(body, tenant: customer, viewer: nil)
    described_class.resolve(body: body, customer_id: tenant.id, viewer: viewer)
  end

  def names(body, tenant: customer, viewer: nil)
    resolve(body, tenant: tenant, viewer: viewer).map(&:name)
  end

  describe ".candidates" do
    it "offers this tenant's entities by name" do
      student = create(:entity, customer: customer, name: "Student")
      create(:entity, customer: customer, name: "Course")
      create(:flowchart, customer: customer, name: "Enroll student")
      create(:entity, customer: other, name: "Foreign")

      candidates = described_class.candidates(customer_id: customer.id)

      expect(candidates.map(&:name)).to eq(["Course", "Student"])
      expect(candidates.map(&:kind).uniq).to eq(%w[entity])
      expect(candidates.map(&:name)).not_to include("Foreign")
    end

    it "offers flowcharts only to the platform owner" do
      student = create(:entity, customer: customer, name: "Student")
      create(:flowchart, customer: customer, name: "Enroll student")

      expect(described_class.kinds_for(viewer: nil)).to eq(%w[entity])
      expect(described_class.kinds_for(viewer: find_or_create_platform_owner)).to eq(%w[entity flowchart])

      owner_candidates = described_class.candidates(
        customer_id: customer.id,
        viewer: find_or_create_platform_owner
      )

      expect(owner_candidates.map(&:name)).to eq(["Student", "Enroll student"])
      expect(owner_candidates.map(&:kind)).to eq(%w[entity flowchart])
    end

    it "prefers an entity's display label for the menu" do
      create(:entity, customer: customer, name: "Student", display_label: "Students")

      candidate = described_class.candidates(customer_id: customer.id).first

      expect(candidate.name).to eq("Student")
      expect(candidate.label).to eq("Students")
      expect(candidate.as_json).to eq("kind" => "entity", "name" => "Student", "label" => "Students")
    end

    # A bridge is created by the app when two entities are associated. The
    # admin never authors one, so it must not be offered.
    it "never offers a bridge entity" do
      target = create(:entity, customer: customer, name: "Course",
                      property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
      source = create(:entity, customer: customer, name: "Student")
      source.associations_json = [{
        "target_entity_id" => target.id,
        "target_entity_name" => target.name,
        "display_field" => "name",
        "display_field_label" => "Name"
      }]
      source.save!
      source.sync_bridge_entities!

      expect(described_class.candidates(customer_id: customer.id).map(&:name))
        .to contain_exactly("Course", "Student")
    end
  end

  describe ".resolve" do
    before_all do
      create(:entity, customer: customer, name: "Student")
      create(:entity, customer: customer, name: "Purchase")
      create(:entity, customer: customer, name: "Purchase Order")
      create(:flowchart, customer: customer, name: "Enroll student")
    end

    it "finds the named entity" do
      expect(names("@Student needs a phone number")).to eq(["Student"])
    end

    it "takes the longest matching name so a prefix cannot win" do
      expect(names("@Purchase Order needs a status")).to eq(["Purchase Order"])
      expect(names("@Purchase needs a status")).to eq(["Purchase"])
    end

    it "matches regardless of the case the admin typed" do
      expect(names("@student and @PURCHASE ORDER")).to eq(["Student", "Purchase Order"])
    end

    it "finds several artifacts in the order they appear, without repeats" do
      mentions = resolve("Bridge @Student to @Purchase, then update @Student again")

      expect(mentions.map(&:name)).to eq(["Student", "Purchase"])
      expect(mentions.map(&:kind)).to eq(%w[entity entity])
    end

    it "resolves a flowchart for the platform owner" do
      mention = resolve("@Enroll student should log the result", viewer: find_or_create_platform_owner).first

      expect(mention.kind).to eq("flowchart")
      expect(mention.record).to be_a(Flowchart)
    end

    it "leaves a flowchart name as prose for a tenant admin" do
      expect(names("@Enroll student should log the result")).to eq([])
    end

    it "stops the name at a word boundary" do
      expect(names("@Student, add a phone")).to eq(["Student"])
      expect(names("(@Student)")).to eq(["Student"])
      expect(names("@Students")).to eq([])
      expect(names("@Student_id")).to eq([])
    end

    # Chinese runs words together, so requiring a space after the name would
    # make a hand-typed mention impossible to resolve.
    it "ends a CJK name at the next character" do
      create(:entity, customer: customer, name: "发票")

      expect(names("@发票加一个到期日")).to eq(["发票"])
      expect(names("@发票 加一个到期日")).to eq(["发票"])
    end

    # `@Invoice` cannot say which kind was meant, so both have to reach the
    # prompt — dropping one would silently retarget the turn.
    it "keeps every artifact answering to a shared name, entity first, when the viewer is the platform owner" do
      create(:entity, customer: customer, name: "Invoice")
      create(:flowchart, customer: customer, name: "Invoice")

      mentions = resolve("@Invoice needs a due date", viewer: find_or_create_platform_owner)

      expect(mentions.map(&:kind)).to eq(%w[entity flowchart])
      expect(mentions.map(&:name)).to eq(%w[Invoice Invoice])
    end

    it "does not resolve a same-named flowchart for a tenant admin" do
      create(:entity, customer: customer, name: "Invoice")
      create(:flowchart, customer: customer, name: "Invoice")

      mentions = resolve("@Invoice needs a due date")

      expect(mentions.map(&:kind)).to eq(%w[entity])
      expect(mentions.map(&:name)).to eq(%w[Invoice])
    end

    it "leaves an unknown @word as prose" do
      expect(names("email @support about @Nonexistent")).to eq([])
    end

    it "ignores a body with no sigil at all" do
      expect(resolve("Student needs a phone number")).to eq([])
      expect(resolve(nil)).to eq([])
    end

    # The parser's whole vocabulary is the tenant's own names, so another
    # tenant's entity cannot be addressed even by spelling it out.
    it "never resolves another tenant's artifact" do
      create(:entity, customer: other, name: "Foreign")

      expect(names("@Foreign needs a field")).to eq([])
      expect(names("@Student needs a field", tenant: other)).to eq([])
    end
  end
end
