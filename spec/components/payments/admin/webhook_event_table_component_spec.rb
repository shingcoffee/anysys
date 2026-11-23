# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Admin::WebhookEventTableComponent, type: :component do
  def event(status:, id:)
    Payments::WebhookEvent.new(
      id: id,
      provider: "stripe",
      event_type: "payment_intent.succeeded",
      signing_merchant_id: "acct_1",
      status: status,
      created_at: Time.zone.parse("2026-09-07 10:30"),
      processed_at: status == "processed" ? Time.zone.parse("2026-09-07 10:31") : nil
    )
  end

  def render_events(events)
    with_request_url("/81721200/admin/maintenance/platform/module_settings/payment/webhook_events") do
      render_inline(described_class.new(events: events))
    end
  end

  it "renders one responsive record and one eligible redrive action" do
    render_events([event(status: "failed", id: 41)])

    expect(page).to have_css("[data-responsive-collection-record='41']", count: 1)
    expect(page).to have_css("[data-responsive-collection-desktop-header]", text: "Provider")
    expect(page).to have_css("[data-responsive-collection-mobile-label]", text: "Merchant")
    expect(page).to have_css("[data-responsive-collection-record='41'][role='row'] > [role='cell']", count: 7)
    expect(page).to have_text("Credit / Debit Card (Stripe)")
    expect(page).to have_text("payment_intent.succeeded")
    expect(page).to have_text(I18n.t("comp_payments.webhook_events.statuses.failed"))
    expect(page).to have_button("Redrive", count: 1)
    expect(page).to have_text(I18n.l(Time.zone.parse("2026-09-07 10:30"), format: :long))
    expect(page).to have_css("form[action$='/payment/webhook_events/41/redrive'][method='post']", count: 1)
  end

  it "offers redrive only for received and failed records" do
    render_events([
      event(status: "received", id: 40),
      event(status: "failed", id: 41),
      event(status: "processed", id: 42)
    ])

    expect(page).to have_css("[data-responsive-collection-record]", count: 3)
    expect(page).to have_css("[data-responsive-collection-record][role='row']", count: 3)
    expect(page).to have_button("Redrive", count: 2)
    expect(page).to have_css("[data-responsive-collection-record='42']", text: I18n.t("comp_payments.webhook_events.statuses.processed"))
    expect(page.find("[data-responsive-collection-record='42']")).not_to have_button("Redrive")
  end

  it "localizes provider and status in zh-CN" do
    I18n.with_locale(:"zh-CN") do
      render_events([event(status: "failed", id: 41)])
      expect(page).to have_text("Credit / Debit Card (Stripe)")
      expect(page).to have_text(I18n.t("comp_payments.webhook_events.statuses.failed"))
    end
  end

  it "uses the shared empty section when there are no events" do
    render_events([])

    expect(page).to have_css("[data-module-settings-empty-section='true']")
    expect(page).to have_text("No webhook events")
  end

  describe "#provider_label" do
    subject { described_class.new(events: []) }

    it "falls back to the raw key for an unknown provider" do
      expect(subject.provider_label("not_a_gateway")).to eq("not_a_gateway")
    end
  end

  describe "#status_label" do
    subject { described_class.new(events: []) }

    it "falls back to the raw key for an unknown status" do
      expect(subject.status_label("unknown")).to eq("unknown")
    end
  end
end
