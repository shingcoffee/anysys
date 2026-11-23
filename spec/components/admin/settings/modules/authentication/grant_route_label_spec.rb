require "rails_helper"

RSpec.describe Admin::Settings::Modules::Authentication::GrantRouteLabel do
  def label(path) = described_class.new(path).label

  %i[en zh-CN].each do |locale|
    context "in #{locale}" do
      around { |example| I18n.with_locale(locale) { example.run } }

      it "distinguishes platform settings and credentials by their translated subsystem" do
        settings = %w[captcha ai_assistant billing].map { |area| label("admin/maintenance/platform/#{area}/settings") }
        credentials = %w[emails sms].map { |area| label("admin/maintenance/platform/#{area}/credentials") }
        expect(settings.uniq.size).to eq(3)
        expect(credentials.uniq.size).to eq(2)
        expect(settings.first).to include(I18n.t("feature_modules.captcha.name"), I18n.t("common.actions.settings"))
        expect(credentials.first).to include(I18n.t("feature_modules.email.name"))
        expect(credentials.last).to include(I18n.t("feature_modules.sms.name"))
      end

      it "gives every current route descriptor a distinct localized name without generic fallbacks" do
        descriptors = AccessPoints::RouteProvider.new.call(customer_id: 81721200)
        expect(descriptors.size).to be > 100
        labels = descriptors.map { |descriptor| label(descriptor.subject_key) }
        duplicates = descriptors.group_by { |descriptor| label(descriptor.subject_key) }
                                .select { |_, matching| matching.size > 1 }
                                .transform_values { |matching| matching.map(&:subject_key) }
        expect(duplicates).to eq({})
        labels.each do |name|
          expect(name).not_to include(I18n.t("settings_people.grant_resources.other"), "/", "_", "Translation missing")
          expect(name.delete("AI")).not_to match(/[a-zA-Z]/) if locale == :"zh-CN"
        end
      end

      it "gives the registered Page shortcuts descriptor a distinct localized resource label" do
        descriptors = AccessPoints::RouteProvider.new.call(customer_id: 81721200)
        shortcut = descriptors.find { |descriptor| descriptor.subject_key == "admin/maintenance/page_shortcuts" }
        expect(shortcut).to be_present
        name = label(shortcut.subject_key)
        expect(name).to include(I18n.t("page_shortcuts.title"))
        expect(name).not_to include(I18n.t("settings_people.grant_resources.other"), "/", "_", "Translation missing")
        expect(descriptors.count { |descriptor| label(descriptor.subject_key) == name }).to eq(1)
      end

      it "does not register a separate custom domains route" do
        descriptors = AccessPoints::RouteProvider.new.call(customer_id: 81721200)
        expect(descriptors.map(&:subject_key)).not_to include("admin/maintenance/platform/custom_domains")
      end

      it "names the nested billing write controllers by their existing localized actions" do
        expect(label("admin/settings/billing/plan_changes")).to include(I18n.t("settings_billing.subscription.cancel_change"))
        expect(label("admin/settings/billing/invoice_payments")).to include(I18n.t("comp_billing.invoice_detail.pay_invoice"))
      end

      it "names all eight SMS audience/campaign resources distinctly under one SMS context" do
        resources = {
          "contacts" => "sms_campaign_http.navigation.contacts",
          "consent_events" => "settings_people.grant_resources.sms_consent_events",
          "entity_syncs" => "settings_people.grant_resources.sms_entity_syncs",
          "segments" => "sms_campaign_http.navigation.segments",
          "campaigns" => "sms_campaign_http.navigation.campaigns",
          "campaign_launches" => "settings_people.grant_resources.sms_campaign_launches",
          "campaign_cancellations" => "settings_people.grant_resources.send_activity_cancellations",
          "campaign_reports" => "settings_people.grant_resources.sms_campaign_reports"
        }
        context = I18n.t("settings_people.grant_label", context: I18n.t("settings_people.areas.module_records"),
                        resource: I18n.t("feature_modules.sms.name"))
        names = resources.map do |controller, key|
          name = label("admin/modules/sms/#{controller}")
          expect(name).to eq(I18n.t("settings_people.grant_label", context: context, resource: I18n.t(key)))
          name
        end
        expect(names.uniq.size).to eq(8)
      end
    end
  end

  it "uses the existing Chinese assistant and invoice titles instead of English controller humanizations" do
    I18n.with_locale(:"zh-CN") do
      expect(label("admin/assistants")).to eq("管理功能 — AI 助手")
      expect(label("admin/settings/billing/invoices")).to eq("设置 — 订阅与账单 — 账单明细")
      expect(label("admin/maintenance/platform/billing/invoices")).to eq("平台管理 — 订阅与账单 — 账单明细")
    end
  end

  it "uses a localized generic resource under the known module for unmapped routes" do
    I18n.with_locale(:"zh-CN") do
      expect(label("admin/modules/emails/future_widget")).to eq("模块记录 — 邮件 — 其他资源")
      expect(label("admin/maintenance/platform/future_module/future_widget")).to eq("平台管理 — 其他资源")
    end
  end

  it "does not use an English-only module translation as context" do
    allow(I18n).to receive(:t).and_call_original
    allow(I18n).to receive(:t).with("feature_modules.future.name", locale: :en, fallback: false, default: nil).and_return("Future subsystem")
    I18n.with_locale(:"zh-CN") do
      expect(label("admin/modules/future/future_widget")).to eq("模块记录 — 其他资源")
    end
  end
end
