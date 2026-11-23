# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flowcharts::LaunchedNoticeComponent, type: :component do
  let(:customer) { create(:customer) }

  def render_notice(flowchart)
    with_request_url("/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}/edit", host: "www.example.com") do
      render_inline(described_class.new(flowchart: flowchart, customer_id: customer.id))
    end
  end

  def stage_draft!(flowchart)
    config = JSON.parse(flowchart.configuration).merge("metadata" => { "note" => "staged" })
    flowchart.update!(configuration: config.to_json)
  end

  it "renders nothing for a draft flowchart" do
    render_notice(create(:flowchart, :simple, customer: customer))

    expect(page).not_to have_css("[role='status']")
  end

  context "when the flowchart is launched" do
    let(:flowchart) { create(:flowchart, :simple, :launched_status, customer: customer) }

    it "says saving stages a draft above the live version" do
      render_notice(flowchart)

      expect(page).to have_css("[role='status']", text: I18n.t("maint_core.flowcharts.editor.launched_edit_notice", live: 1))
    end

    it "names the pending draft version once one is saved" do
      stage_draft!(flowchart)
      render_notice(flowchart.reload)

      expect(page).to have_text(I18n.t("maint_core.flowcharts.editor.launched_draft_notice", live: 1, draft: 2))
    end

    it "posts the launch to the flowchart's launch route" do
      render_notice(flowchart)

      expect(page).to have_css("form[action='/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}/launch'][method='post']")
      expect(page).to have_button(I18n.t("maint_core.flowcharts.launch_latest"))
    end
  end

  it "renders in zh-CN" do
    flowchart = create(:flowchart, :simple, :launched_status, customer: customer)

    I18n.with_locale(:"zh-CN") { render_notice(flowchart) }

    expect(page).to have_text("线上页面正在运行 v1")
    expect(page).to have_button("发布最新版本")
  end
end
