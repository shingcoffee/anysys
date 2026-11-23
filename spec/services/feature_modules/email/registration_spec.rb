# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::Email::Registration do
  it_behaves_like "a feature module registration", key: "email", name: "Email"

  let_it_be(:customer) { create(:customer) }

  around { |ex| Current.set(customer: customer) { ex.run } }

  describe ".configuration_schema" do
    it "includes daily_send_cap only" do
      expect(described_class.configuration_schema.keys).to contain_exactly("daily_send_cap")
    end
  end

  describe ".input_contract" do
    it "registers template_id without template_key" do
      expect(described_class.input_contract_properties).to include("template_id")
      expect(described_class.input_contract_properties).not_to include("template_key")
    end
  end

  describe ".sidebar_contributions" do
    let(:controller) { double("controller", current_customer: customer) }
    let!(:email_module) { enable_module!("email", customer, name: "Email") }

    it "lists send_activities, audience, content, analytics" do
      keys = described_class.sidebar_contributions(controller)[:entries].map(&:entry_key)
      expect(keys).to eq(%w[send_activities audience content analytics])
    end

    it "points send_activities at send_activities only" do
      entry = described_class.sidebar_contributions(controller)[:entries].find { |e| e.entry_key == "send_activities" }
      expect(entry.path.call(customer)).to eq("/#{customer.id}/admin/modules/emails/send_activities")
      expect(entry.match_prefix).to eq(["/#{customer.id}/admin/modules/emails/send_activities"])
    end

    it "points audience at lists (lists + suppressions tabs)" do
      entry = described_class.sidebar_contributions(controller)[:entries].find { |e| e.entry_key == "audience" }
      expect(entry.path.call(customer)).to eq("/#{customer.id}/admin/modules/emails/lists")
      expect(entry.match_prefix).to eq([
        "/#{customer.id}/admin/modules/emails/lists",
        "/#{customer.id}/admin/modules/emails/suppressions"
      ])
    end

    it "matches content to templates" do
      entry = described_class.sidebar_contributions(controller)[:entries].find { |e| e.entry_key == "content" }
      expect(entry.path.call(customer)).to eq("/#{customer.id}/admin/modules/emails/templates")
      expect(entry.match_prefix).to eq([
        "/#{customer.id}/admin/modules/emails/templates"
      ])
    end

    it "matches analytics to dashboard and health" do
      entry = described_class.sidebar_contributions(controller)[:entries].find { |e| e.entry_key == "analytics" }
      expect(entry.path.call(customer)).to eq("/#{customer.id}/admin/modules/emails/dashboard")
      expect(entry.match_prefix).to include(
        "/#{customer.id}/admin/modules/emails/dashboard",
        "/#{customer.id}/admin/modules/emails/health"
      )
    end

    it "does not put settings in module sidebar entries" do
      keys = described_class.sidebar_contributions(controller)[:entries].map(&:entry_key)
      expect(keys).not_to include("settings")
    end

    it "exposes daily_cap and template_tokens under settings contributions" do
      settings = described_class.sidebar_contributions(controller)[:settings].map(&:entry_key)
      expect(settings).to eq(%w[daily_cap template_tokens])
    end
  end

  describe ".entries_for" do
    it "raises for an unknown entry_key" do
      expect { described_class.entries_for(entry_key: "unknown", params: {}) }
        .to raise_error(ArgumentError, /unknown entry_key: unknown/)
    end

    it "resolves send_activities and lists configs" do
      %w[send_activities lists].each do |key|
        config = described_class.entries_for(entry_key: key, params: {})
        expect(config[:title]).to be_present
        expect(config[:columns]).to be_present
        expect(config[:scope]).to respond_to(:count)
      end
    end
  end
end
