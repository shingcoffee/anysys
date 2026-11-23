# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::Prompt::Context do
  subject(:context) { described_class.new(conversation: conversation.reload, mode: :entity) }

  let(:customer) { create(:customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer) }

  describe "#website_enabled?" do
    it "is false when the Website module is off for the tenant" do
      expect(context.website_enabled?).to be(false)
    end

    it "is true when the Website module is on for the tenant" do
      enable_module!("website", customer)

      expect(context.website_enabled?).to be(true)
    end

    it "does not see another tenant's module" do
      enable_module!("website", create(:customer))

      expect(context.website_enabled?).to be(false)
    end
  end

  describe "#website and #website_pages" do
    it "are nil and empty when the tenant has no website yet" do
      expect(context.website).to be_nil
      expect(context.website_pages).to eq([])
    end

    it "lists the tenant's pages in navigation order" do
      website = create(:website, customer: customer)
      second = create(:website_page, website: website, position: 2, title: "Contact")
      first = create(:website_page, :home, website: website, position: 1)

      expect(context.website).to eq(website)
      expect(context.website_pages).to eq([first, second])
    end

    it "never reaches another tenant's website" do
      other = create(:website, customer: create(:customer))
      create(:website_page, website: other)

      expect(context.website).to be_nil
      expect(context.website_pages).to eq([])
    end
  end

  describe "#focused_website_page" do
    let(:website) { create(:website, customer: customer) }
    let(:page) { create(:website_page, website: website) }

    before { AiAssistant::Assistant::Artifact.assign_record!(conversation, record: page) }

    it "is the pinned website page when the module is on" do
      enable_module!("website", customer)

      expect(context.focused_website_page).to eq(page)
    end

    it "is nil once the module is turned off" do
      expect(context.focused_website_page).to be_nil
    end

    it "is never mistaken for a focused entity" do
      enable_module!("website", customer)

      expect(context.focused_entity).to be_nil
    end
  end

  it "has no focused website page when an entity is pinned" do
    enable_module!("website", customer)
    entity = create(:entity, customer: customer, name: "Employee")
    AiAssistant::Assistant::Artifact.assign_record!(conversation, record: entity)

    expect(context.focused_website_page).to be_nil
    expect(context.focused_entity).to eq(entity)
  end

  describe "#domain_catalog" do
    it "lists this tenant's domains and the non-bridge entities placed in each" do
      academics = create(:entity_domain, customer: customer, name: "Academics", color: "blue")
      create(:entity_domain, customer: create(:customer), name: "Foreign")
      course = create(:entity, customer: customer, name: "Course")
      create(:entity, customer: customer, name: "Orphan")
      EntityDomains::Memberships.place!(course, academics)

      expect(context.domain_catalog).to eq(
        [
          {
            "name" => "Academics",
            "description" => nil,
            "color" => "blue",
            "entities" => ["Course"]
          }
        ]
      )
    end

    it "is empty when the tenant has no domains" do
      create(:entity_domain, customer: create(:customer), name: "Foreign")

      expect(context.domain_catalog).to eq([])
    end
  end

  describe "#native_tools?" do
    it "is false when no generation vendor is assigned" do
      expect(context.native_tools?).to eq(false)
    end

    it "is true when the active generation vendor supports native tools" do
      create(:ai_assistant_provider_settings)

      expect(context.native_tools?).to eq(true)
    end
  end

  describe "#uploads" do
    it "is the conversation's upload set, built once" do
      message = create(:ai_assistant_message, conversation: conversation, customer: customer)
      Current.set(customer: customer) do
        message.images.attach(io: StringIO.new("\x89PNG\r\n\x1A\n"), filename: "shop.png", content_type: "image/png")
      end

      uploads = context.uploads

      expect(uploads).to be_a(Websites::Assistant::Uploads)
      expect(uploads.all.map(&:filename)).to eq(["shop.png"])
      expect(context.uploads).to be(uploads)
    end
  end

  describe "#pending_operation_proposal" do
    def invocation_for(convo, **overrides)
      create(
        :operation_invocation,
        :awaiting_confirmation,
        customer: convo.customer,
        user: convo.user,
        conversation_id: convo.id,
        operation: "update_entity",
        input: { "updates" => [{ "entity" => "Student" }] },
        **overrides
      )
    end

    def park!(convo: conversation, **proposal)
      create(
        :ai_assistant_message,
        :assistant,
        conversation: convo,
        customer: convo.customer,
        metadata: { "pending_confirmation" => proposal.stringify_keys }
      )
    end

    it "returns the operation and input of a live invocation on this conversation" do
      invocation = invocation_for(conversation)
      park!("kind" => "operation", "invocation_id" => invocation.id, "customer_id" => customer.id)

      expect(context.pending_operation_proposal).to eq(
        "operation" => "update_entity",
        "input" => invocation.input
      )
      expect(context.pending_operation_proposal).to be(context.pending_operation_proposal)
    end

    it "is nil for a flowchart proposal" do
      park!("kind" => "flowchart", "document" => { "intent" => "apply_flowchart" })

      expect(context.pending_operation_proposal).to be_nil
    end

    it "is nil when the invocation belongs to another conversation or tenant" do
      other_conversation = create(:ai_assistant_conversation, customer: customer)
      foreign_customer = create(:customer)
      foreign_user = create(:user, :admin, customer: foreign_customer)
      foreign_conversation = create(:ai_assistant_conversation, customer: foreign_customer, user: foreign_user)
      other_invocation = invocation_for(other_conversation)
      foreign_invocation = invocation_for(foreign_conversation)
      park!("kind" => "operation", "invocation_id" => other_invocation.id, "customer_id" => customer.id)
      park!("kind" => "operation", "invocation_id" => foreign_invocation.id, "customer_id" => foreign_customer.id)

      expect(context.pending_operation_proposal).to be_nil
    end

    it "is nil once the invocation is no longer awaiting confirmation" do
      invocation = invocation_for(conversation, status: "succeeded")
      park!("kind" => "operation", "invocation_id" => invocation.id, "customer_id" => customer.id)

      expect(context.pending_operation_proposal).to be_nil
    end
  end
end

