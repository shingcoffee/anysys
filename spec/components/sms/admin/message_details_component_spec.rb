# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sms::Admin::MessageDetailsComponent, type: :component do
  let(:message) { build_stubbed(:sms_message, status: "sent", delivery_attempts: 0) }

  def render_details
    render_inline(described_class.new(message: message))
  end

  def field_group(label)
    page.find("dt", text: label, exact_text: true, normalize_ws: true).find(:xpath, "..")
  end

  describe "status presentation" do
    {
      "queued" => "badge-default", "pending" => "bg-info-subtle",
      "sent" => "bg-info-subtle", "delivered" => "badge-success",
      "failed" => "badge-danger", "unknown" => "badge-default",
      "suppressed" => "badge-default", "expired" => "badge-warning"
    }.each do |status, badge_class|
      %i[en zh-CN].each do |locale|
        it "renders #{status} with a visible localized explanation in #{locale}" do
          message.status = status
          I18n.with_locale(locale) do
            render_details
            label_key = status == "expired" ? "sms.statuses.expired" : "common.status.#{status}"
            expect(page).to have_css(".badge.#{badge_class}", text: I18n.t(label_key))
            status_group = field_group(I18n.t("common.labels.status"))
            expect(status_group[:class]).to include("md:col-span-2")
            description_id = status_group.find("dd")[:"aria-describedby"]
            expect(status_group).to have_css("p[id='#{description_id}']", text: I18n.t("sms_presentation.status_help.#{status}"))
            expect(rendered_content).not_to include("translation_missing", "Translation missing")
          end
        end
      end
    end

    it "describes sent as provider acceptance, separately from recipient delivery" do
      render_details
      expect(page).to have_text("The provider accepted this message. This does not confirm delivery to the recipient.")
      expect(page).to have_text("When the provider accepted the message, not when it was delivered.")
      expect(page).not_to have_css(".badge-success")
    end

    it "keeps unknown neutral and conceals stale failure details" do
      message.assign_attributes(status: "unknown", failure_code: "STALE_FAILURE", failure_message: "stale failure text")
      render_details
      expect(page).to have_text("Unknown does not mean failed.")
      expect(page).not_to have_css(".badge-danger")
      expect(rendered_content).not_to include("STALE_FAILURE", "stale failure text")
    end
  end

  it "renders paired fields in a responsive card with long text wrapping" do
    message.assign_attributes(template_key: "template_" * 80, vendor_message_id: "vendor_" * 80,
                              metadata: { "provider_status" => "status_" * 80 })
    render_details
    expect(page).to have_css(".card > dl.grid.grid-cols-1.gap-4")
    expect(page.find(".card > dl")[:class].split).to include("p-4", "sm:p-6", "md:grid-cols-2")
    expect(page).to have_css("h2", text: "Message Details")
    expect(page).to have_text(message.to)
    expect(page).to have_text("Aliyun SMS")
    [message.template_key, message.vendor_message_id, message.metadata["provider_status"]].each do |text|
      expect(page).to have_css("dd.break-words", text: text)
    end
  end

  it "shows unknown expiry and segments, other absent facts as not recorded, and valid zero attempts" do
    message.assign_attributes(provider: nil, vendor_message_id: nil, vars: {}, metadata: {})
    render_details
    expect(field_group("Expires at")).to have_css("dd", text: "Unknown")
    expect(field_group("Provider-reported segments")).to have_css("dd", text: "Unknown")
    ["Provider", "Vendor Message ID", "Dispatch started at", "Sent At", "Delivered At", "Provider event time", "Provider status", "Variables"].each do |label|
      expect(field_group(label)).to have_css("dd", text: "Not recorded")
    end
    expect(field_group("Delivery attempts")).to have_css("dd", exact_text: "0", normalize_ws: true)
    expect(page).not_to have_css("time")
  end

  [nil, 0, -1, "0", "-1", "2.5", 2.5, "estimate", ""].each do |segments|
    it "does not present #{segments.inspect} as an actual segment count" do
      message.metadata = { "provider_segments" => segments, "estimated_segments" => 99 }
      render_details
      expect(field_group("Provider-reported segments")).to have_css("dd", exact_text: "Unknown", normalize_ws: true)
    end
  end

  [3, "3"].each do |segments|
    it "shows a positive actual provider segment count #{segments.inspect}" do
      message.metadata = { "provider_status" => "DELIVRD", "provider_segments" => segments }
      render_details
      expect(field_group("Provider-reported segments")).to have_css("dd", exact_text: "3", normalize_ws: true)
      expect(field_group("Provider status")).to have_css("dd", exact_text: "DELIVRD", normalize_ws: true)
    end
  end

  %i[en zh-CN].each do |locale|
    it "localizes all timestamps and parses the ISO provider event time in #{locale}" do
      timestamp = Time.zone.local(2026, 6, 15, 10, 30)
      message.assign_attributes(dispatch_started_at: timestamp, sent_at: timestamp + 1.minute,
                                delivered_at: timestamp + 2.minutes, expires_at: timestamp + 5.minutes,
                                metadata: { "provider_occurred_at" => (timestamp + 3.minutes).iso8601 })
      I18n.with_locale(locale) do
        render_details
        [timestamp, timestamp + 1.minute, timestamp + 2.minutes, timestamp + 5.minutes, timestamp + 3.minutes].each do |time|
          expect(page).to have_css("time[datetime='#{time.iso8601}']", text: I18n.l(time, format: :long))
        end
        expect(page).to have_css("time", count: 5)
      end
    end
  end

  ["invalid-date", "2026-99-99T25:99:00Z", 123].each do |timestamp|
    it "handles an invalid provider timestamp #{timestamp.inspect} as not recorded" do
      message.metadata = { "provider_occurred_at" => timestamp }
      render_details
      expect(field_group("Provider event time")).to have_css("dd", exact_text: "Not recorded", normalize_ws: true)
      expect(page).not_to have_css("time")
    end
  end

  it "renders escaped failed-only details and localizes canned failures at render time" do
    message.assign_attributes(status: "failed", failure_code: "<script>bad()</script>",
                              failure_message: Sms::Message::FAILURE_DELIVERY)
    I18n.with_locale(:"zh-CN") do
      render_details
      expect(page).to have_text(I18n.t("sms.failures.delivery_failed"))
      expect(page).to have_text("<script>bad()</script>")
      expect(page).to have_text(I18n.t("common.labels.em_dash"))
      expect(page).not_to have_css("script")
    end
  end

  it "shows a failure message even without a failure code" do
    message.assign_attributes(status: "failed", failure_code: nil, failure_message: "<b>Provider rejected</b>")
    render_details
    expect(field_group("Failure")).to have_text("Not recorded — <b>Provider rejected</b>", normalize_ws: true)
    expect(page).not_to have_css("b")
  end

  %w[queued pending sent delivered suppressed expired].each do |status|
    it "does not display stale failure facts for #{status}" do
      message.assign_attributes(status: status, failure_code: "STALE_FAILURE", failure_message: "stale failure text")
      render_details
      expect(rendered_content).not_to include("STALE_FAILURE", "stale failure text")
      expect(page).not_to have_css("dt", exact_text: "Failure")
    end
  end

  %i[en zh-CN].each do |locale|
    it "redacts every variable value on the server and escapes names in #{locale}" do
      secrets = ["654321-secret", "private@example.test", "sensitive payload"]
      message.vars = { "code" => secrets[0], "<img src=x onerror=alert(1)>" => secrets[1], "long_" * 80 => secrets[2] }
      message.raw_response = { "private" => "private-provider-response" }
      message.metadata = { "template_snapshot" => { "vars" => message.vars } }
      I18n.with_locale(locale) do
        render_details
        expect(page).to have_text("<img src=x onerror=alert(1)>")
        expect(page).to have_css("dl dl dd", exact_text: I18n.t("sms_presentation.redacted"), count: 3)
        expect(page).not_to have_css("img, [title], [data-vars]")
        expect(rendered_content).not_to include(*secrets, "private-provider-response")
      end
    end
  end

  it "keeps the new locale keys and interpolation tokens in parity" do
    translations = %w[en zh-CN].map do |locale|
      YAML.safe_load_file(Rails.root.join("config/locales/sms_presentation.#{locale}.yml")).fetch(locale).fetch("sms_presentation")
    end
    flatten = lambda do |hash, prefix = []|
      hash.flat_map do |key, value|
        path = prefix + [key]
        value.is_a?(Hash) ? flatten.call(value, path).to_a : [[path.join("."), value.scan(/%\{([^}]+)\}/).flatten.sort]]
      end.to_h
    end
    expect(flatten.call(translations[0])).to eq(flatten.call(translations[1]))
  end
end
