# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::RecordJourneysComponent, type: :component do
  let(:customer) { create(:customer) }
  let(:record) { build_stubbed(:entity_entry, customer: customer) }
  let(:follow_up) { build_stubbed(:journey, customer: customer, key: "follow_up", name: "Follow up") }
  let(:renew) { build_stubbed(:journey, customer: customer, key: "renew", name: "Renew") }

  def start(journey) = Journeys::RecordStarts::Start.new(journey: journey, page: nil, field: nil)
  def start_path(key) = "/#{customer.id}/member/entities/#{record.entity_id}/entries/#{record.id}/journeys/#{key}"

  it "offers one start button per journey, posting to the member start for this record" do
    render_inline(described_class.new(starts: [start(follow_up), start(renew)], record: record, customer: customer))

    section = page.find("section[data-role='record-journeys'][aria-labelledby='record-journeys-title']")
    expect(section).to have_css("h2#record-journeys-title", text: I18n.t("member.record_journeys.title"))
    expect(section).to have_text(I18n.t("member.record_journeys.description"))
    button = section.find("form[action='#{start_path('follow_up')}'][method='post'] button[type='submit'][data-journey-start='follow_up']")
    expect(button.text).to include(I18n.t("journeys.runtime.start_from_record", name: "Follow up"))
    expect(section).to have_css("form[action='#{start_path('renew')}'][class*='w-full'] button[data-journey-start='renew']",
                                text: I18n.t("journeys.runtime.start_from_record", name: "Renew"))
  end

  it "renders nothing without a start" do
    render_inline(described_class.new(starts: nil, record: record, customer: customer))

    expect(page).not_to have_css("[data-role='record-journeys']")
  end

  it "renders in zh-CN" do
    I18n.with_locale(:"zh-CN") { render_inline(described_class.new(starts: [start(follow_up)], record: record, customer: customer)) }

    expect(page).to have_css("h2", text: "后续步骤")
  end
end
