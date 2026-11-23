# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/entities/show.html.erb", type: :view do
  let(:customer) { double("Customer", id: 12345678) }
  let(:active) { true }
  let(:bridge) { false }
  let(:entity) do
    double("Entity", to_param: "7", display_label: "Course", active?: active, category_bridge?: bridge,
           color: "slate", icon: "folder", input_fields: [], computed_fields: [], calculated_fields: [], searchable_field_keys: [])
  end

  before do
    assign(:entity, entity)
    assign(:filters, [])
    assign(:rows, [])
    assign(:columns, [])
    assign(:pagination, { total: 0, page: 1, per_page: 25, total_pages: 1 })
    assign(:density, "comfortable")
    assign(:setting, double("IndexSetting", visible_column_keys: []))
    without_partial_double_verification { allow(view).to receive(:current_customer).and_return(customer) }
  end

  it "keeps Create Entry before Export CSV when the table is empty with full-page navigation" do
    render
    html = Nokogiri::HTML.fragment(rendered)
    actions = html.css("a.btn")
    expect(actions.map { |action| action.text.strip }).to eq([I18n.t("admin_misc.entities.entry_form.create"), I18n.t("admin_misc.entities.show.export_csv")])
    expect(actions.first["href"]).to eq("/12345678/admin/entities/7/entries/new")
    expect(actions.first["data-turbo-frame"]).to eq("_top")
    expect(actions.map { |action| action["class"] }).to all(include("min-h-11 w-full sm:w-auto"))
    expect(actions.first["class"]).to include("btn-primary")
    expect(actions.last["class"]).to include("btn-secondary")
  end

  it "keeps Create Entry discoverable in Chinese when a search has no matches" do
    controller.params[:q] = "no matches"
    I18n.with_locale(:"zh-CN") { render }
    expect(rendered).to have_link("创建条目", href: "/12345678/admin/entities/7/entries/new")
    expect(rendered).to have_link("导出 CSV", href: "/12345678/admin/entities/7.csv?q=no+matches")
  end

  context "with an inactive entity" do
    let(:active) { false }

    it "does not offer creation" do
      render
      expect(rendered).not_to have_link(I18n.t("admin_misc.entities.entry_form.create"))
    end
  end

  context "with a bridge entity" do
    let(:bridge) { true }

    it "does not offer creation" do
      render
      expect(rendered).not_to have_link(I18n.t("admin_misc.entities.entry_form.create"))
    end
  end
end
