# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Entities::LifecycleSummaryComponent, type: :component do
  let(:status) do
    { "name" => "Status", "name_slug" => "status", "html_type" => "select",
      "config" => { "source" => "manual", "options" => [
        { "label" => "Draft", "value" => "draft", "default" => true },
        { "label" => "Submitted", "value" => "submitted" }, { "label" => "Approved", "value" => "approved" }
      ] },
      "lifecycle" => { "transitions" => [
        { "from" => "draft", "to" => "submitted", "by" => %w[member admin] },
        { "from" => "submitted", "to" => "approved", "by" => %w[system] }
      ] } }
  end

  it "summarises the changes by option label with who may make each" do
    render_inline(described_class.new(attribute: status))

    expect(page).to have_css("details[data-field='lifecycle'] summary", text: "2 status changes")
    expect(page).to have_text("New records start at Draft")
    rows = page.all("li", visible: :all).map { |row| row.text(:all).squish }
    expect(rows).to eq(["Draft → Submitted · Members and Admins", "Submitted → Approved · System"])
  end

  it "uses the singular for a single change and translates for zh-CN" do
    single = status.merge("lifecycle" => { "transitions" => [status["lifecycle"]["transitions"].first] })
    render_inline(described_class.new(attribute: single))
    expect(page).to have_css("summary", text: "1 status change")

    I18n.with_locale(:"zh-CN") { render_inline(described_class.new(attribute: single)) }
    expect(page).to have_css("summary", text: "1 项状态变更")
    expect(page).to have_text(I18n.t("comp_admin.lifecycle_summary.starts_at", state: "Draft", locale: :"zh-CN"))
    expect(page).to have_text(%w[会员 管理员].to_sentence(locale: :"zh-CN"))
  end

  it "renders nothing when no lifecycle is in force" do
    expect(render_inline(described_class.new(attribute: status.except("lifecycle"))).to_html).to be_blank
    expect(render_inline(described_class.new(attribute: status.merge("html_type" => "text"))).to_html).to be_blank
    expect(render_inline(described_class.new(attribute: nil)).to_html).to be_blank
  end
end
