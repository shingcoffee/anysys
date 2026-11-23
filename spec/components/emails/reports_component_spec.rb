# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::ReportsComponent, type: :component do
  let(:customer) { create(:customer) }
  let(:since) { 2.days.ago.beginning_of_day }
  let(:until_date) { Time.current.end_of_day }
  let(:empty_report) do
    {
      since: since,
      until_date: until_date,
      totals: { sent: 0, delivered: 0, bounced: 0, complained: 0, suppressed: 0, opened: 0, clicked: 0 },
      daily: (since.to_date..until_date.to_date).map { |date| { date: date, sent: 0, delivered: 0, bounced: 0, opened: 0, clicked: 0 } },
      send_activities: {}
    }
  end

  around do |example|
    Current.set(customer: customer) { example.run }
  end

  before do
    allow_any_instance_of(described_class).to receive(:current_customer_id).and_return(customer.id)
  end

  it "renders the empty report" do
    render_inline(described_class.new(report: empty_report, since: since, until_date: until_date, csv_path: "/csv", url: "/reports"))

    expect(page).to have_text(I18n.t("admin_modules.emails.analytics.reports.empty_daily"))
    expect(page).to have_text(I18n.t("admin_modules.emails.analytics.reports.empty_send_activities"))
    expect(page).to have_link(I18n.t("admin_modules.emails.analytics.reports.export_csv"), href: "/csv")
  end

  it "resolves send activity names" do
    campaign = create(:email_send_activity, customer: customer, name: "Summer Sale")
    report = empty_report.deep_dup
    report[:send_activities] = { campaign.id => 4 }

    render_inline(described_class.new(report: report, since: since, until_date: until_date, csv_path: "/csv", url: "/reports"))

    expect(page).to have_text("Summer Sale")
    expect(page).to have_text("4")
  end
end
