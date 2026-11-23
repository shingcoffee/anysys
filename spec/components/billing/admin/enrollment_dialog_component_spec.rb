# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::EnrollmentDialogComponent, type: :component do
  let(:plan) { build(:billing_plan, :with_trial, code: "pro", name: "Pro", description: "Team workspace") }
  let(:item) { double(key: "page", label: "Pages") }
  let(:key) { "987b603e-cb63-4b40-a8b5-5fc5db7e5aa8" }
  let(:catalog) do
    double(
      "catalog",
      enrollment_open?: false,
      plan_price: "$99.00 USD",
      interval_label: "per month",
      trial_offer?: true,
      plan_trial: "14 days free",
      enabled_items: [item],
      unlimited?: false,
      limit_display: "10",
      customer_id: 12345678,
      request_key: key,
      coupon_code_value: nil,
      field_options: { aria: { invalid: false, describedby: nil } },
      field_error: nil
    )
  end

  def render_dialog(**overrides)
    overrides.each { |name, value| allow(catalog).to receive(name).and_return(value) }
    render_inline described_class.new(plan: plan, catalog: catalog)
  end

  it "opens enrollment from a button into a named dialog" do
    render_dialog
    expect(page).to have_css("button[data-action='modal-dialog#open'][aria-haspopup='dialog'][aria-controls='subscribe-plan-pro']", text: "Review subscription")
    expect(page).to have_css('[data-controller="modal-dialog"][data-modal-dialog-open-value="false"]')
    dialog = page.find("dialog#subscribe-plan-pro", visible: :all)
    expect(dialog).to have_css("h2", text: "Subscribe to Pro", visible: :all)
    expect(dialog).to have_css("*", text: "Team workspace", visible: :all)
    expect(dialog).to have_css("form[action='/12345678/admin/settings/billing/subscription']", visible: :all)
    expect(dialog).to have_css('input[name="billing_subscription[plan_code]"][value="pro"]', visible: :all)
    expect(dialog).to have_css("input[name='billing_subscription[request_key]'][value='#{key}']", visible: :all)
    expect(page).not_to have_css("summary, details")
  end

  it "shows the trial badge and included limits inside the dialog" do
    render_dialog
    dialog = page.find("dialog#subscribe-plan-pro", visible: :all)
    expect(dialog).to have_css("*", text: "14 days free", visible: :all)
    expect(dialog).to have_css("*", text: "Included plan limits", visible: :all)
    expect(dialog).to have_css("*", text: "Pages", visible: :all)
    expect(dialog).to have_css("*", text: "10", visible: :all)
  end

  it "opens the dialog on a 422 enrollment error" do
    render_dialog(enrollment_open?: true, coupon_code_value: "INVALID",
      field_options: { aria: { invalid: true, describedby: "billing_subscription_coupon_code_error" } })
    expect(page).to have_css('[data-controller="modal-dialog"][data-modal-dialog-open-value="true"]')
    expect(page).to have_field("billing_subscription[coupon_code]", with: "INVALID", visible: :all)
  end

  it "localizes trigger and dialog copy without missing translations" do
    I18n.with_locale(:"zh-CN") do
      render_dialog
      expect(page).to have_button(I18n.t("settings_billing.subscription.review_subscription"))
      expect(page).to have_css("h2", text: I18n.t("settings_billing.subscription.enrollment_dialog.title", plan: "Pro"), visible: :all)
      expect(page).to have_css("dialog#subscribe-plan-pro", text: I18n.t("settings_billing.subscription.enrollment_dialog.included_limits"), visible: :all)
      expect(page).not_to have_css(".translation_missing")
    end
  end
end
