# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Stream do
  let(:customer) { create(:customer) }
  let(:other_customer) { create(:customer) }
  let(:user) { create(:user, :admin, customer: customer) }
  let(:conversation) do
    create(:ai_assistant_conversation, customer: customer, user: user)
  end

  describe ".broadcast_artifact" do
    it "replaces the stable artifact root using the conversation tenant and user" do
      entity = create(:entity, customer: customer)
      page_record = create(:page, customer: customer, entity: entity)
      AiAssistant::Assistant::Artifact.assign_record!(conversation, record: page_record)
      broadcast = nil
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to) do |stream, **options|
        broadcast = { stream: stream, options: options }
      end

      Current.customer = other_customer
      described_class.broadcast_artifact(conversation)

      expect(broadcast.fetch(:stream)).to eq(described_class.for_conversation(conversation))
      expect(broadcast.dig(:options, :target)).to eq(described_class::ARTIFACT_ID)
      expect(broadcast.dig(:options, :html)).to include(
        %(id="#{described_class::ARTIFACT_ID}"),
        Rails.application.routes.url_helpers.admin_maintenance_page_preview_path(
          customer.id,
          page_record,
          embed: 1
        )
      )
      expect(broadcast.dig(:options, :html)).not_to include(
        "/#{other_customer.id}/admin/"
      )
    ensure
      Current.reset
    end
  end

  describe ".status_html" do
    it "returns empty html when the status text is blank" do
      expect(described_class.status_html(nil)).to eq("")
      expect(described_class.status_html("")).to eq("")
      expect(described_class.status_html("   ")).to eq("")
    end

    it "wraps present text in a live status pill" do
      html = described_class.status_html("Working…")
      expect(html).to include(
        "inline-flex items-center gap-1.5 rounded-full bg-accent-subtle px-2.5 py-1 text-xs font-medium text-accent-text"
      )
      expect(html).to include("size-1.5 animate-pulse rounded-full bg-accent")
      expect(html).to include("Working…")
      expect(html).not_to include("max-w-2xl text-center text-caption")
    end
  end

  describe ".broadcast_status" do
    it "broadcasts empty html for a blank status" do
      broadcast = nil
      allow(Turbo::StreamsChannel).to receive(:broadcast_update_to) do |stream, **options|
        broadcast = { stream: stream, options: options }
      end

      described_class.broadcast_status(conversation, "")

      expect(broadcast.fetch(:stream)).to eq(described_class.for_conversation(conversation))
      expect(broadcast.dig(:options, :target)).to eq(described_class::STATUS_ID)
      expect(broadcast.dig(:options, :html)).to eq("")
    end

    it "broadcasts a status pill for present text" do
      broadcast = nil
      allow(Turbo::StreamsChannel).to receive(:broadcast_update_to) do |stream, **options|
        broadcast = { stream: stream, options: options }
      end

      described_class.broadcast_status(conversation, I18n.t("ai_assistant.assistant.status.thinking"))

      expect(broadcast.dig(:options, :html)).to include(
        I18n.t("ai_assistant.assistant.status.thinking")
      )
      expect(broadcast.dig(:options, :html)).to include("rounded-full bg-accent-subtle")
    end
  end
end
