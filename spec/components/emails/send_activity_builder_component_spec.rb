# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::SendActivityBuilderComponent, type: :component do
  let(:customer) { create(:customer) }
  let(:send_activity) do
    build(:email_send_activity, customer: customer, name: "Spring Newsletter", timezone: "UTC", send_timing: "now")
  end
  let(:templates) { [] }
  let(:lists) { [] }
  let(:url) { "/#{customer.id}/admin/modules/emails/send_activities" }

  def render_wizard(activity: send_activity, method: :post)
    render_inline(
      described_class.new(
        send_activity: activity,
        templates: templates,
        lists: lists,
        url: url,
        method: method
      )
    )
  end

  describe "STEPS" do
    it "follows who → what → when → review" do
      expect(described_class::STEPS).to eq(%w[audience content schedule review])
    end
  end

  it "renders all step panels and Stimulus wizard mount" do
    render_wizard

    expect(page).to have_css("[data-controller='email-send-activity-wizard']")
    expect(page).to have_css("[data-email-send-activity-wizard-target='step'][data-step='audience']")
    expect(page).to have_css("[data-email-send-activity-wizard-target='step'][data-step='content'].hidden", visible: :all)
    expect(page).to have_css("[data-email-send-activity-wizard-target='step'][data-step='schedule'].hidden", visible: :all)
    expect(page).to have_css("[data-email-send-activity-wizard-target='step'][data-step='review'].hidden", visible: :all)
    expect(page).to have_text(I18n.t("admin_modules.emails.send_activities.wizard.steps.schedule"))
    expect(page).not_to have_text("Setup")
  end

  it "puts Name and Send Now on the schedule step" do
    render_wizard

    expect(page).to have_css("[data-step='schedule'] input[name='email_send_activity[name]']", visible: :all)
    expect(page).to have_css("[data-step='schedule'] input[name='email_send_activity[send_timing]'][value='now']", visible: :all)
  end

  it "puts list on audience and template on content" do
    render_wizard

    audience = page.find("[data-step='audience']")
    expect(audience).to have_css("label", text: I18n.t("admin_modules.emails.send_activities.form.lists_label"))
    expect(audience).to have_css("[data-email-send-activity-wizard-target='listsContainer']")
    expect(audience).to have_css("[data-email-send-activity-wizard-target='listSelect']")
    expect(audience).to have_css("button[data-action='click->email-send-activity-wizard#addList']")
    expect(page.find("[data-step='content']", visible: :all)).to have_select(
      I18n.t("admin_modules.emails.send_activities.form.template_label"), visible: :all
    )
  end

  it "marks required fields and exposes Create links plus refresh after each select" do
    render_wizard

    audience = page.find("[data-step='audience']")
    expect(audience).to have_css("label.form-label-required", text: I18n.t("admin_modules.emails.send_activities.form.lists_label"))
    expect(audience).to have_css("button[data-action='email-send-activity-wizard#refreshLists']")
    expect(audience).to have_link(
      I18n.t("admin_modules.emails.send_activities.form.create_list"),
      href: "/#{customer.id}/admin/modules/emails/lists/new",
      target: "_blank"
    )

    content = page.find("[data-step='content']", visible: :all)
    expect(content).to have_css("label.form-label-required", visible: :all)
    expect(content).to have_css("button[data-action='email-send-activity-wizard#refreshTemplates']", visible: :all)
    expect(content).to have_link(
      I18n.t("admin_modules.emails.send_activities.form.create_template"),
      href: "/#{customer.id}/admin/modules/emails/templates/new",
      visible: :all
    )

    expect(page).to have_css("[data-step='schedule'] label.form-label-required", visible: :all)
  end

  it "renders progress badges, checks, and connectors for all steps" do
    render_wizard

    expect(page).to have_css("[data-email-send-activity-wizard-target='stepBadge']", count: 4)
    expect(page).to have_css("[data-email-send-activity-wizard-target='stepCheck']", count: 4, visible: :all)
    expect(page).to have_css("[data-email-send-activity-wizard-target='stepConnector']", count: 3)
    expect(page).to have_css("[data-email-send-activity-wizard-target='timezoneFields'].hidden", visible: :all)
  end

  it "shows Continue and hides Create until review (server-rendered defaults)" do
    render_wizard

    expect(page).to have_button(I18n.t("common.actions.continue"))
    expect(page).to have_css("[data-email-send-activity-wizard-target='submitButton'].hidden", visible: :all)
  end
end
