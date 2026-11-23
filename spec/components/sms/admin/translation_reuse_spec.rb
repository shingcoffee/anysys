# frozen_string_literal: true

require "rails_helper"

RSpec.describe "SMS presentation translation reuse", type: :component do
  def strings(hash, prefix = [])
    hash.each_with_object({}) do |(key, value), result|
      path = prefix + [key.to_s]
      if value.is_a?(Hash)
        result.merge!(strings(value, path))
      elsif value.is_a?(String)
        result[path.join(".")] = value
      end
    end
  end

  def locale_strings(path, locale)
    strings(YAML.safe_load_file(path, aliases: true).fetch(locale))
  end

  it "keeps every new UI string distinct from existing byte-identical paired translations" do
    ui_file = Rails.root.join("config/locales/sms_campaign_ui.en.yml")
    ui_strings = locale_strings(ui_file, "en")
    existing = Rails.root.glob("config/locales/*.en.yml").reject { |path| path == ui_file }.each_with_object({}) do |path, result|
      chinese_path = path.to_s.sub(/\.en\.yml\z/, ".zh-CN.yml")
      next unless File.exist?(chinese_path)

      chinese = locale_strings(chinese_path, "zh-CN")
      locale_strings(path, "en").each do |key, value|
        (result[value] ||= []) << key if chinese.key?(key)
      end
    end
    duplicates = ui_strings.filter_map { |key, value| [key, existing[value]] if existing.key?(value) }.to_h
    expect(duplicates).to be_empty
    expect(ui_strings.values.uniq.size).to eq(ui_strings.size)
  end

  it "preserves the exact English of reused dynamic field, state, step and metric labels" do
    expected = {
      fields: { name: "Name", phone: "Phone number", country_code: "Country code", timezone: "Timezone",
                status: "Contact status", action: "Action", description: "Description", entity_id: "Entity" },
      statuses: { active: "Active", archived: "Archived", unknown: "Unknown", granted: "Granted", revoked: "Revoked",
                  draft: "Draft", scheduled: "Scheduled", running: "Running", completed: "Completed", cancelled: "Cancelled",
                  failed: "Failed", pending: "Pending", admitted: "Admitted", skipped: "Skipped", queued: "Queued",
                  sent: "API accepted", delivered: "Delivered", suppressed: "Suppressed", expired: "Expired" },
      "campaigns.steps": { audience: "Audience", content: "Content", schedule: "Schedule", review: "Review" },
      metrics: { pending_count: "Pending", admitted_count: "Admitted", api_accepted_count: "API accepted",
                 delivered_count: "Delivered", failed_count: "Failed", unknown_count: "Unknown", queued_count: "Queued",
                 suppressed_count: "Suppressed", expired_count: "Expired", skipped_count: "Skipped", cancelled_count: "Cancelled" },
      sync_outcomes: { created: "Created", updated: "Updated", unchanged: "Unchanged", invalid: "Invalid", conflict: "Conflict", conflicts: "Conflict" },
      encodings: { gsm7: "GSM-7", gsm_7: "GSM-7", ucs2: "UCS-2", ucs_2: "UCS-2", utf16: "UTF-16" },
      campaigns: { send_now: "Send now", cancelled_at: "Cancelled at" },
      reasons: { phone_invalid: "Invalid phone number", invalid_phone: "Invalid phone number",
                 no_eligible_contacts: "Add eligible consented contacts", scheduled_at_required: "Set a scheduled time" }
    }
    component = Sms::Admin::TabsComponent.new(tabs: [{ label: "Campaigns", path: "/campaigns", active: true }])
    I18n.with_locale(:en) do
      render_inline(component)
      expected.each do |group, labels|
        labels.each { |name, text| expect(component.label_text(group, name)).to eq(text) }
      end
    end
  end

  it "translates reused keys at render time with paired interpolation variables and canonical Chinese" do
    component = Sms::Admin::TabsComponent.new(tabs: [{ label: "Campaigns", path: "/campaigns", active: true }])
    I18n.with_locale(:en) { render_inline(component) }
    I18n.with_locale(:"zh-CN") do
      expect(component.label_text(:fields, :name)).to eq(I18n.t("common.labels.name"))
      expect(component.label_text(:statuses, :unknown)).to eq(I18n.t("common.status.unknown"))
      expect(component.label_text("campaigns.steps", :review)).to eq(I18n.t("admin_modules.emails.send_activities.wizard.steps.review"))
      expect(component.label_text(:fields, :name)).not_to eq("Name")
    end
    Sms::Admin::BaseComponent::LABEL_KEYS.each_value do |labels|
      labels.each_value do |key|
        english = I18n.t(key, locale: :en, raise: true)
        chinese = I18n.t(key, locale: :"zh-CN", raise: true)
        expect(english.scan(/%\{([^}]+)\}/).flatten.sort).to eq(chinese.scan(/%\{([^}]+)\}/).flatten.sort)
      end
    end
  end
end
