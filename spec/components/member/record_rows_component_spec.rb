# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::RecordRowsComponent, type: :component do
  let(:customer) { create(:customer) }
  let(:entity) { build_stubbed(:entity, customer: customer, display_label: "assoc_cart_product") }
  let(:record) { build_stubbed(:entity_entry, customer: customer) }
  let(:columns) { [Member::RecordRows::Column.new(slug: "product", label: "Product"), Member::RecordRows::Column.new(slug: "quantity", label: "Quantity")] }
  let(:line) { instance_double(EntityEntry, to_param: "41") }

  before { allow(line).to receive(:display_text) { |slug| { "product" => "Tea", "quantity" => "3" }.fetch(slug) } }

  def managing_page(modes) = build_stubbed(:page, customer: customer, configuration: { form_settings: { modes: modes } }.to_json)

  def render_section(rows: [line], page: nil)
    section = Member::RecordRows::Section.new(entity: entity, title: "Cart items", columns: columns, rows: rows, page: page, record: record)
    render_inline(described_class.new(section: section, customer: customer))
  end

  it "lists the rows read-only when no page manages them" do
    render_section

    expect(page).to have_css("[data-record-rows='#{entity.id}'] h2", text: "Cart items")
    expect(page).to have_css("th", text: "Quantity")
    expect(page).to have_css("td", text: "Tea")
    expect(page).to have_css("dd", text: "3")
    expect(page).not_to have_link(I18n.t("member.record_rows.add"))
    expect(page).not_to have_link(I18n.t("member.record_rows.change"))
    expect(page).not_to have_button(I18n.t("member.record_rows.remove"))
  end

  it "offers Add, Change and Remove when the page adds and changes rows" do
    rows_page = managing_page(%w[create update])
    render_section(page: rows_page)

    expect(page).to have_link(I18n.t("member.record_rows.add"), href: "/#{customer.id}/member/pages/#{rows_page.id}/rows/new?record=#{record.id}")
    expect(page).to have_link(I18n.t("member.record_rows.change"), href: "/#{customer.id}/member/pages/#{rows_page.id}/rows/41/edit", count: 2)
    expect(page).to have_css("form[action='/#{customer.id}/member/pages/#{rows_page.id}/rows/41']" \
                             "[data-turbo-confirm='#{I18n.t('member.record_rows.remove_confirm')}'] input[name='_method'][value='delete']",
                             count: 2, visible: :all)
  end

  it "offers Remove without Change or Add when the page only changes rows" do
    render_section(page: managing_page(%w[update]))

    expect(page).not_to have_link(I18n.t("member.record_rows.add"))
    expect(page).to have_link(I18n.t("member.record_rows.change"))
    expect(page).to have_button(I18n.t("member.record_rows.remove"))
  end

  it "says when there is nothing yet" do
    render_section(rows: [], page: managing_page(%w[create]))

    expect(page).to have_text(I18n.t("member.record_rows.empty"))
    expect(page).to have_link(I18n.t("member.record_rows.add"))
    expect(page).not_to have_css("table")
  end
end
