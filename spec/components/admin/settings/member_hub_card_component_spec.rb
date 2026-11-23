require "rails_helper"

RSpec.describe Admin::Settings::MemberHubCardComponent, type: :component do
  let_it_be(:customer) { create(:customer) }

  let(:editable_presenter) do
    instance_double(
      Admin::Settings::MemberHubCardPresenter,
      key: :modules, name: "Modules",
      description: "Read-only surfaces shipped by feature modules.",
      editable?: true, total_count: 3, enabled_count: 2,
      configure_path: "/#{customer.id}/admin/settings/member/sources/modules"
    )
  end

  let(:locked_presenter) do
    instance_double(
      Admin::Settings::MemberHubCardPresenter,
      key: :builtin, name: "Built-in",
      description: "Always-visible.", editable?: false,
      total_count: 3, enabled_count: 3,
      configure_path: "/#{customer.id}/admin/settings/member/sources/builtin"
    )
  end

  def render_card(presenter) = render_inline(described_class.new(presenter: presenter))

  it "renders source name and description" do
    render_card(editable_presenter)
    expect(page).to have_text("Modules")
    expect(page).to have_text("Read-only surfaces shipped by feature modules.")
  end

  it "shows count summary when editable" do
    render_card(editable_presenter)
    expect(page).to have_text("3 pages")
    expect(page).to have_text("2 visible to members")
  end

  it "renders 'Configure' CTA for editable sources" do
    render_card(editable_presenter)
    expect(page).to have_link("Configure", href: editable_presenter.configure_path)
  end

  it "renders 'View' CTA + locked badge for non-editable sources" do
    render_card(locked_presenter)
    expect(page).to have_link("View", href: locked_presenter.configure_path)
    expect(page).to have_text("Always available")
  end
end
