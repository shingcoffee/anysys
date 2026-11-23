# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Entities::DomainDeleteDialogComponent, type: :component do
  let(:customer) { create(:customer) }
  let(:domain) { create(:entity_domain, customer: customer, name: "Academics") }
  let(:student) { create(:entity, :with_name_status_schema, customer: customer, name: "Student", display_label: "Student") }

  def render_dialog(locale: :en)
    I18n.with_locale(locale) { render_inline(described_class.new(domain: domain, customer_id: customer.id)) }
  end

  def dialog = page.find("dialog#entity-domain-#{domain.id}-delete", visible: :all)

  it "opens a narrow danger dialog from a delete button" do
    render_dialog

    trigger = page.find("[data-controller='modal-dialog'] > button[data-action='modal-dialog#open']")
    expect(trigger).to have_text(I18n.t("maint_core.entity_domains.index.delete_domain"))
    expect(trigger["aria-controls"]).to eq("entity-domain-#{domain.id}-delete")
    expect(dialog[:class]).to include("sm:max-w-lg")
    expect(dialog).to have_css("h2", text: I18n.t("maint_core.entity_domains.delete_dialog.title", name: "Academics"),
                                     visible: :all)
  end

  it "lists what the delete removes and posts the delete to the whole page" do
    EntityDomains::Memberships.place!(student, domain)
    EntityDomains::Memberships.place!(create(:entity, :shared, name: "Country"), domain)
    create(:entity_entry, customer: customer, entity: student)
    create(:page, customer: customer, entity: student)
    create(:journey, customer: customer, entity_domain: domain)

    render_dialog

    lines = dialog.all("[data-role='domain-delete-dialog'] li", visible: :all).map { |node| node.text(:all).strip }
    expect(lines).to eq([
      I18n.t("maint_core.entity_domains.delete_dialog.entities", count: 1),
      I18n.t("maint_core.entity_domains.delete_dialog.records", count: 1),
      I18n.t("maint_core.entity_domains.delete_dialog.pages", count: 1),
      I18n.t("maint_core.entity_domains.delete_dialog.journeys", count: 1)
    ])
    expect(dialog).to have_text(I18n.t("maint_core.entity_domains.delete_dialog.shared", count: 1))
    form = dialog.find("form[action='/#{customer.id}/admin/maintenance/entity_domains/#{domain.id}']", visible: :all)
    expect(form["data-turbo-frame"]).to eq("_top")
    expect(form).to have_css("input[name='_method'][value='delete']", visible: :all)
    expect(form).to have_button(I18n.t("maint_core.entity_domains.delete_dialog.confirm"), visible: :all)
  end

  it "skips the shared note when every entity is the customer's own" do
    render_dialog

    expect(dialog).not_to have_text(I18n.t("maint_core.entity_domains.delete_dialog.shared", count: 1))
  end

  it "explains why the domain cannot be deleted while another domain links in" do
    order = create(:entity, customer: customer, name: "Order", display_label: "Order")
    order.update!(associations: [{ "target_entity_id" => student.id, "target_entity_name" => "Student",
                                   "display_field" => "name", "display_field_label" => "Name" }].to_json)
    EntityDomains::Memberships.place!(student, domain)
    EntityDomains::Memberships.place!(order, create(:entity_domain, customer: customer))

    render_dialog

    expect(dialog).to have_css("[role='alert']", text: I18n.t("maint_core.entity_domains.delete_dialog.blocked_title"), visible: :all)
    expect(dialog).to have_text(I18n.t("maint_core.entity_domains.errors.linked_from_outside", names: "Order"))
    expect(dialog).not_to have_button(I18n.t("maint_core.entity_domains.delete_dialog.confirm"), visible: :all)
    expect(dialog).to have_button(I18n.t("common.actions.cancel"), visible: :all)
  end

  it "renders in zh-CN" do
    render_dialog(locale: :"zh-CN")

    expect(dialog).to have_text(I18n.t("maint_core.entity_domains.delete_dialog.confirm", locale: :"zh-CN"))
    expect(page).to have_button(I18n.t("maint_core.entity_domains.index.delete_domain", locale: :"zh-CN"))
  end
end
