# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::Artifact do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other) { create(:customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer) }

  # There is deliberately no id-only pin: every write goes through the record,
  # so the tenant check cannot be skipped by a caller holding an id.
  describe ".assign_record!" do
    it "pins a tenant-owned entity on the conversation" do
      entity = create(:entity, customer: customer, name: "Student")

      described_class.assign_record!(conversation, record: entity)

      conversation.reload
      expect(conversation.artifact_kind).to eq("entity")
      expect(conversation.artifact_id).to eq(entity.id)
    end

    it "rejects an unsupported record" do
      expect {
        described_class.assign_record!(conversation, record: create(:customer))
      }.to raise_error(ArgumentError)
    end

    it "rejects a record from another tenant" do
      foreign = create(:entity, customer: other)

      expect {
        described_class.assign_record!(conversation, record: foreign)
      }.to raise_error(ArgumentError)
    end
  end

  describe ".resolve" do
    it "returns the pinned record when it belongs to the conversation customer" do
      entity = create(:entity, customer: customer, name: "Student")
      described_class.assign_record!(conversation, record: entity)
      resolved = described_class.resolve(conversation, customer: customer)
      expect(resolved.kind).to eq("entity")
      expect(resolved.record).to eq(entity)
      expect(resolved.label).to eq(entity.display_label)
    end

    it "returns nil when the pinned record belongs to another customer" do
      foreign = create(:entity, customer: other, name: "Foreign")
      conversation.update!(artifact_kind: "entity", artifact_id: foreign.id)
      expect(described_class.resolve(conversation, customer: customer)).to be_nil
    end

    it "returns nil when nothing is pinned" do
      expect(described_class.resolve(conversation, customer: customer)).to be_nil
    end

    it "returns a pinned flowchart for the platform owner" do
      conversation.update!(user: find_or_create_platform_owner)
      entity = create(:entity, customer: customer)
      flowchart = create(:flowchart, customer: customer)
      described_class.assign_record!(conversation, record: flowchart)

      resolved = described_class.resolve(conversation, customer: customer)
      expect(resolved.kind).to eq("flowchart")
      expect(resolved.record).to eq(flowchart)
    end

    it "hides a pinned flowchart from a tenant admin" do
      entity = create(:entity, customer: customer)
      flowchart = create(:flowchart, customer: customer)
      described_class.assign_record!(conversation, record: flowchart)

      expect(described_class.resolve(conversation, customer: customer)).to be_nil
    end

    context "with a pinned website page" do
      let(:website) { create(:website, customer: customer) }
      let(:website_page) { create(:website_page, website: website, title: "About us") }

      before { described_class.assign_record!(conversation, record: website_page) }

      it "resolves it by title while the Website module is on" do
        enable_module!("website", customer)

        resolved = described_class.resolve(conversation, customer: customer)

        expect(resolved.kind).to eq("website_page")
        expect(resolved.record).to eq(website_page)
        expect(resolved.label).to eq("About us")
      end

      it "hides it once the Website module is off" do
        expect(described_class.resolve(conversation, customer: customer)).to be_nil
      end

      it "never resolves another tenant's website page" do
        enable_module!("website", customer)
        foreign = create(:website_page, website: create(:website, customer: other))
        conversation.update!(artifact_kind: "website_page", artifact_id: foreign.id)

        expect(described_class.resolve(conversation, customer: customer)).to be_nil
      end
    end
  end

  describe ".kind_for" do
    it "names a website page" do
      website_page = create(:website_page, website: create(:website, customer: customer))

      expect(described_class.kind_for(website_page)).to eq("website_page")
    end
  end

  describe ".pick" do
    it "prefers page over flowchart over entity" do
      entity = create(:entity, customer: customer)
      flowchart = create(:flowchart, customer: customer)
      page = create(:page, customer: customer, entity: entity)
      expect(described_class.pick(page: page, flowchart: flowchart, entity: entity)).to eq(page)
      expect(described_class.pick(page: nil, flowchart: flowchart, entity: entity)).to eq(flowchart)
      expect(described_class.pick(page: nil, flowchart: nil, entity: entity)).to eq(entity)
    end

    it "prefers a website page over everything else" do
      entity = create(:entity, customer: customer)
      page = create(:page, customer: customer, entity: entity)
      website_page = create(:website_page, website: create(:website, customer: customer))

      expect(described_class.pick(website_page: website_page, page: page, entity: entity)).to eq(website_page)
    end
  end
end
