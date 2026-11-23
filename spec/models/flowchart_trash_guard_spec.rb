# frozen_string_literal: true

require "rails_helper"

# A flowchart bound to a launched page cannot be taken offline or soft-deleted
# (Flowchart#pages_keep_their_processing). Draft pages do not block taking it
# offline.
RSpec.describe Flowchart, "pages keep their processing" do
  let_it_be(:customer) { create(:customer) }
  let(:flowchart) { create(:flowchart, :simple, :launched_status, customer: customer) }

  def bind(page)
    page.update_column(:flowchart_id, flowchart.id)
    flowchart.reload
  end

  def offline_message(count)
    I18n.t("maint_core.errors.validations.flowchart_offline_used_by_pages", count: count)
  end

  def delete_message(count)
    I18n.t("maint_core.errors.validations.flowchart_delete_used_by_pages", count: count)
  end

  it "refuses to take a flowchart offline while a launched page is bound to it" do
    bind(create(:page, :launched, customer: customer))

    expect(flowchart.update(status: :draft)).to be(false)
    expect(flowchart.errors[:base]).to include(offline_message(1))
    expect(flowchart.reload).to be_launched
  end

  it "refuses to soft-delete a flowchart while a launched page is bound to it" do
    bind(create(:page, :launched, customer: customer))

    expect(flowchart.soft_delete).to be_falsey
    expect(flowchart.errors[:base]).to include(delete_message(1))
    expect(flowchart.reload).to be_launched
    expect(flowchart).not_to be_deleted
  end

  it "lets a flowchart go offline when it is bound only to draft pages" do
    bind(create(:page, customer: customer, launched: false))

    expect(flowchart.update(status: :draft)).to be(true)
    expect(flowchart.reload).to be_draft
  end

  it "still refuses to soft-delete a flowchart bound only to draft pages" do
    bind(create(:page, customer: customer, launched: false))

    expect(flowchart.soft_delete).to be_falsey
    expect(flowchart.errors[:base]).to include(delete_message(1))
    expect(flowchart.reload).not_to be_deleted
  end
end
