# frozen_string_literal: true

require "rails_helper"

module FeatureModules
  module ZzzCatalog
    class Registration
      def self.sidebar_contributions(_context)
        {
          entries: [
            ModuleContribution.new(
              label: "Alpha",
              entry_key: "alpha",
              path: ->(id) { "/#{id}/admin/modules/zzz_catalogs/alpha" }
            ),
            ModuleContribution.new(
              label: "Beta",
              entry_key: "beta",
              path: ->(id) { "/#{id}/admin/modules/zzz_catalogs/beta" }
            ),
            ModuleContribution.new(
              label: "Gamma",
              entry_key: "gamma",
              path: ->(id) { "/#{id}/admin/modules/zzz_catalogs/gamma" }
            )
          ],
          settings: [
            ModuleContribution.new(
              label: "Config",
              entry_key: "config",
              path: ->(id) { "/#{id}/admin/settings/modules/zzz_catalogs/config" }
            )
          ]
        }
      end
    end
  end

  module ZzzSettingsOnly
    class Registration
      def self.sidebar_contributions(_context)
        {
          entries: [],
          settings: [
            ModuleContribution.new(
              label: "Status",
              entry_key: "status",
              path: ->(id) { "/#{id}/admin/settings/modules/zzz_settings_onlies/status" }
            )
          ]
        }
      end
    end
  end
end

RSpec.describe Dashboard::ModuleCards do
  let(:customer) { create(:customer) }

  def reset_module_catalog!(active_optional: [])
    FeatureModules::Module.find_each do |fm|
      attrs = if fm.key == "authentication"
        { status: :active, required: true }
      elsif active_optional.include?(fm.key)
        { status: :active, required: false }
      else
        { required: false, status: :inactive }
      end
      fm.update!(attrs)
    end
  end

  def card_for(key)
    described_class.call(customer: customer).find { |card| card.key == key }
  end

  describe "known catalog" do
    before do
      reset_module_catalog!(active_optional: %w[email payment sms captcha ai_assistant])
      %w[email payment sms captcha ai_assistant].each { |key| enable_module!(key, customer) }
    end

    it "orders cards by module name" do
      expect(described_class.call(customer: customer).map(&:key)).to eq(
        %w[ai_assistant captcha email payment sms authentication]
      )
    end

    it "assigns every known module to a stable hub section" do
      sections = described_class.call(customer: customer).to_h { |c| [c.key, c.section] }
      expect(sections).to eq(
        "ai_assistant" => :growth,
        "captcha" => :growth,
        "email" => :communication,
        "payment" => :communication,
        "sms" => :communication,
        "authentication" => :records
      )
    end

    it "exposes record links without customer settings destinations" do
      card = card_for("payment")
      expect(card.links.map(&:href)).to eq([
        "/#{customer.id}/admin/modules/payments/transactions",
        "/#{customer.id}/admin/modules/payments/reconciliations"
      ])
      expect(described_class.call(customer: customer).flat_map(&:links).map(&:href)).not_to include(a_string_including("/admin/settings/"))
    end

    it "builds the authentication card with users primary and events secondary" do
      cid = customer.id
      card = card_for("authentication")
      expect(card.name).to eq(I18n.t("feature_modules.authentication.name"))
      expect(card.description).to eq(I18n.t("admin_misc.dashboard.modules.blurbs.authentication"))
      expect(card.primary).to eq(
        Dashboard::Link.new(
          label: I18n.t("feature_modules.authentication.entries.users"),
          href: "/#{cid}/admin/modules/authentication/users"
        )
      )
      expect(card.secondaries).to eq([
        Dashboard::Link.new(
          label: I18n.t("feature_modules.authentication.entries.events"),
          href: "/#{cid}/admin/modules/authentication/events"
        )
      ])
    end

    it "builds the email card with templates primary and send-activity/lists secondaries" do
      cid = customer.id
      card = card_for("email")
      expect(card.primary).to eq(
        Dashboard::Link.new(
          label: I18n.t("feature_modules.email.titles.templates"),
          href: "/#{cid}/admin/modules/emails/templates"
        )
      )
      expect(card.secondaries).to eq([
        Dashboard::Link.new(
          label: I18n.t("feature_modules.email.titles.send_activities"),
          href: "/#{cid}/admin/modules/emails/send_activities"
        ),
        Dashboard::Link.new(
          label: I18n.t("feature_modules.email.entries.audience"),
          href: "/#{cid}/admin/modules/emails/lists"
        )
      ])
    end

    it "builds the payment card without a checkout URL" do
      cid = customer.id
      card = card_for("payment")
      expect(card.primary.href).to eq("/#{cid}/admin/modules/payments/transactions")
      expect(card.primary.label).to eq(I18n.t("feature_modules.payment.entries.transactions"))
      expect(card.secondaries.map(&:href)).to eq(["/#{cid}/admin/modules/payments/reconciliations"])
      expect(card.secondaries.map(&:label)).to eq([
        I18n.t("feature_modules.payment.entries.reconciliations")
      ])
      expect(card.links.map(&:href)).not_to include(a_string_including("/subscriptions"))
      hrefs = [card.primary.href, *card.secondaries.map(&:href)]
      expect(hrefs.grep(/checkout/)).to eq([])
    end

    it "builds the SMS card with campaigns primary and audience plus messages beside it" do
      cid = customer.id
      card = card_for("sms")
      expect(card.primary.href).to eq("/#{cid}/admin/modules/sms/campaigns")
      expect(card.primary.label).to eq(I18n.t("sms_campaign_http.navigation.campaigns"))
      expect(card.secondaries).to eq([
        Dashboard::Link.new(
          label: I18n.t("feature_modules.email.entries.audience"),
          href: "/#{cid}/admin/modules/sms/contacts"
        ),
        Dashboard::Link.new(
          label: I18n.t("feature_modules.sms.entries.messages"),
          href: "/#{cid}/admin/modules/sms/messages"
        )
      ])
    end

    it "keeps settings-only captcha visible without linking to settings" do
      card = card_for("captcha")
      expect(card.primary).to be_nil
      expect(card.secondaries).to eq([])
      expect(card.links).to eq([])
    end

    it "builds the AI assistant card with assistant primary" do
      card = card_for("ai_assistant")
      expect(card.primary).to eq(
        Dashboard::Link.new(
          label: I18n.t("admin_misc.dashboard.modules.open_assistant"),
          href: "/#{customer.id}/admin/assistant"
        )
      )
      expect(card.secondaries).to eq([])
    end

    it "links the Website card to its module page list" do
      enable_module!("website", customer)

      expect(card_for("website").primary.href).to eq("/#{customer.id}/admin/modules/website")
    end
  end

  describe "unknown module fallback" do
    before { reset_module_catalog!(active_optional: []) }

    it "uses the first entries href as primary and the next two as secondaries" do
      enable_module!("zzz_catalog", customer, name: "ZZZ Catalog")
      card = card_for("zzz_catalog")
      cid = customer.id
      expect(card.primary).to eq(
        Dashboard::Link.new(label: "Alpha", href: "/#{cid}/admin/modules/zzz_catalogs/alpha")
      )
      expect(card.secondaries).to eq([
        Dashboard::Link.new(label: "Beta", href: "/#{cid}/admin/modules/zzz_catalogs/beta"),
        Dashboard::Link.new(label: "Gamma", href: "/#{cid}/admin/modules/zzz_catalogs/gamma")
      ])
      expect(card.description).to eq(
        I18n.t("admin_misc.dashboard.modules.blurbs.fallback", name: "ZZZ Catalog")
      )
    end

    it "keeps a future settings-only module visible without linking to settings" do
      enable_module!("zzz_settings_only", customer, name: "ZZZ Settings")
      card = card_for("zzz_settings_only")
      expect(card.primary).to be_nil
      expect(card.secondaries).to eq([])
      expect(card.links).to eq([])
    end

    it "returns a nil primary when the module has no sidebar paths" do
      enable_module!("zzz_empty", customer, name: "ZZZ Empty")
      card = card_for("zzz_empty")
      expect(card.primary).to be_nil
      expect(card.secondaries).to eq([])
    end

    it "assigns unknown modules to the other section with a full link list" do
      enable_module!("zzz_catalog", customer, name: "ZZZ Catalog")
      card = card_for("zzz_catalog")
      expect(card.section).to eq(:other)
      expect(card.links.size).to eq(3)
    end
  end
end
