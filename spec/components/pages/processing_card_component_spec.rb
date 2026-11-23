# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::ProcessingCardComponent, type: :component do
  let(:customer) { create(:customer) }
  let(:page_record) { create(:page, customer: customer) }
  let(:editable) { true }

  subject(:component) { described_class.new(page: page_record, customer_id: customer.id, editable: editable) }

  def render_component
    with_request_url("/#{customer.id}/admin/maintenance/pages/#{page_record.id}", host: "www.example.com") do
      render_inline(component)
    end
  end

  it "links the current flowchart and marks the default with a badge" do
    render_component

    expect(page).to have_css("[data-role='page-processing']")
    expect(page).to have_link(page_record.flowchart.name, href: /\/admin\/maintenance\/flowcharts\/#{page_record.flowchart_id}/)
    expect(page).to have_text(I18n.t("comp_misc.page_processing.default_badge"))
    expect(page).to have_css(".badge", text: I18n.t("maint_core.flowcharts.status.launched"))
  end

  it "explains why the bound flowchart doesn't fit the page's entity" do
    bind_page_flowchart(page_record, steps: [{
      "action" => "set_record_fields",
      "config" => { "assignments" => [{ "key" => "not_a_field", "value" => "1" }] }
    }])
    render_component

    problems = page.find("[data-role='processing-problems']")
    expect(problems).to have_text(I18n.t("maint_core.errors.page_launch.submission_process_incompatible",
                                         entity: page_record.entity.display_label))
    expect(problems).to have_text("not_a_field")
  end

  it "shows no problems for a compatible flowchart" do
    render_component

    expect(page).to have_no_css("[data-role='processing-problems']")
  end

  it "labels a draft option with the draft suffix" do
    draft = create(:flowchart, :draft, customer: customer, name: "WIP save")
    render_component

    expect(page).to have_select("page[flowchart_id]", with_options: [
      I18n.t("comp_misc.page_processing.draft_option", name: draft.name)
    ])
  end

  it "renders the rebind form when editable" do
    render_component

    form = page.find("form")
    expect(form["action"]).to include("/admin/maintenance/pages/#{page_record.id}/flowchart")
    expect(form.find("input[name='_method']", visible: :all)[:value].downcase).to eq("patch")
    expect(page).to have_button(I18n.t("common.actions.save"))
  end

  context "when not editable" do
    let(:editable) { false }

    it "shows the current flowchart without a picker" do
      render_component

      expect(page).to have_link(page_record.flowchart.name)
      expect(page).not_to have_css("select[name='page[flowchart_id]']")
      expect(page).not_to have_button(I18n.t("common.actions.save"))
    end
  end
end
