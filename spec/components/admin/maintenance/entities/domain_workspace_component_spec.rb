# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Entities::DomainWorkspaceComponent, type: :component do
  let(:customer) { create(:customer) }
  let(:academics) { create(:entity_domain, customer: customer, name: "Academics", description: "Courses and students") }
  let(:commerce) { create(:entity_domain, customer: customer, name: "Commerce") }
  let!(:student) { create(:entity, customer: customer, name: "Student", display_label: "Student") }
  let!(:invoice) { create(:entity, customer: customer, name: "Invoice", display_label: "Invoice") }
  let!(:bridge) { create(:entity, customer: customer, name: "assoc_student_course", category: :bridge) }
  let!(:country) { create(:entity, :shared, name: "Country", display_label: "Country") }
  let(:base) { "/#{customer.id}/admin/maintenance/entities" }

  before do
    Current.customer = customer
    EntityDomains::Memberships.place!(student, academics)
    EntityDomains::Memberships.place!(bridge, academics)
    EntityDomains::Memberships.place!(invoice, commerce)
  end

  after { Current.reset }

  def render_workspace(selected: nil, query: nil, kind: nil, journeys: Journey.for_customer(customer.id).to_a, locale: :en)
    entities = Entity.where(customer_id: [customer.id, nil]).by_name.to_a
    sections = EntityDomains::Layout.call(customer_id: customer.id, entities: entities)
    I18n.with_locale(locale) do
      render_inline(described_class.new(sections: sections, journeys: journeys, customer_id: customer.id,
                                        selected: selected, query: query, kind: kind))
    end
  end

  def entity_ids = page.all("[data-role='domain-entities'] [data-entity-id]").map { |row| row["data-entity-id"].to_i }

  it "lists the domains in a rail with their counts and a trailing entry for unplaced entities" do
    create(:journey, customer: customer, entity_domain: academics)

    render_workspace

    rail = page.find("nav[aria-label='#{I18n.t('maint_core.entity_domains.index.navigator_label')}'] .card")
    expect(rail.all("[data-entity-domain-key]").map { |link| link["data-entity-domain-key"] })
      .to eq([academics.id.to_s, commerce.id.to_s, "ungrouped"])
    first = rail.find("[data-entity-domain-key='#{academics.id}']")
    expect(first["aria-current"]).to eq("page")
    expect(first).to have_text("Academics")
    expect(first).to have_text([I18n.t("maint_core.entity_domains.index.entity_count", count: 2),
                                I18n.t("maint_core.entity_domains.workspace.journey_count", count: 1)].join(" · "))
    expect(rail.find("[data-entity-domain-key='ungrouped']")).to have_text(I18n.t("maint_core.entity_domains.workspace.not_in_domain"))
    expect(rail).to have_link(I18n.t("maint_core.entity_domains.index.new_domain"), href: "/#{customer.id}/admin/maintenance/entity_domains/new")
    expect(page).to have_css("ul.lg\\:hidden a", text: "Commerce")
  end

  it "shows the selected domain's header, entities and journeys" do
    create(:journey, customer: customer, entity_domain: academics, name: "Enrolment")
    create(:journey, customer: customer, entity_domain: commerce, name: "Checkout")

    render_workspace(selected: academics.id)

    header = page.find("[data-role='domain-header']")
    expect(header).to have_css("h2", text: "Academics")
    expect(header).to have_text("Courses and students")
    expect(header).to have_text(I18n.t("maint_core.entity_domains.workspace.bridge_count", count: 1))
    expect(header).to have_link(I18n.t("maint_core.entities.index.new_entity"), href: "#{base}/new?domain_id=#{academics.id}")
    expect(header).to have_link(I18n.t("maint_core.entity_domains.index.edit_domain"),
                                href: "/#{customer.id}/admin/maintenance/entity_domains/#{academics.id}/edit")
    expect(header).to have_button(I18n.t("maint_core.entity_domains.index.delete_domain"))
    expect(entity_ids).to contain_exactly(student.id, bridge.id)

    journeys = page.find("[data-role='domain-journeys']")
    expect(journeys).to have_text("Enrolment")
    expect(journeys).not_to have_text("Checkout")
    expect(journeys).to have_link(I18n.t("journeys.admin.new"), href: "#{base}/journeys/new?domain_id=#{academics.id}")
    expect(journeys).to have_link(I18n.t("journeys.admin.generate"), href: "#{base}/journeys/generate?domain_id=#{academics.id}")
    expect(journeys).not_to have_css("[data-role='journey-workflow-map']")
  end

  it "maps how the selected domain's journeys connect once it lists two" do
    create(:journey, customer: customer, entity_domain: academics, name: "Enrolment")
    create(:journey, customer: customer, entity_domain: academics, name: "Graduation")

    render_workspace(selected: academics.id)

    map = page.find("[data-role='domain-journeys'] [data-role='journey-workflow-map']")
    expect(map).to have_text(I18n.t("journeys.admin.map.title"))
    expect(map).to have_text(I18n.t("journeys.admin.map.empty"))
  end

  it "describes a domain without a description and invites a first entity" do
    empty = create(:entity_domain, customer: customer, name: "Empty")

    render_workspace(selected: empty.id)

    expect(page.find("[data-role='domain-header']")).to have_text(I18n.t("maint_core.entity_domains.workspace.no_description"))
    entities = page.find("[data-role='domain-entities']")
    expect(entities).to have_text(I18n.t("maint_core.entity_domains.index.empty_domain"))
    expect(entities).to have_link(I18n.t("maint_core.entities.index.new_entity"), href: "#{base}/new?domain_id=#{empty.id}")
  end

  it "searches and filters the selected domain's entities, keeping the domain in every link" do
    render_workspace(selected: academics.id, query: "ASSOC")
    expect(entity_ids).to eq([bridge.id])
    expect(page.find("form[role='search']", visible: :all)).to have_css("input[name='domain_id'][value='#{academics.id}']", visible: :all)

    render_workspace(selected: academics.id, kind: "entity")
    expect(entity_ids).to eq([student.id])
    active = page.find("[role='group'] a[aria-current='true']")
    expect(active[:href]).to eq("#{base}?domain_id=#{academics.id}&kind=entity")

    render_workspace(selected: academics.id, query: "nothing")
    expect(page).to have_text(I18n.t("maint_core.entity_domains.index.no_matches"))
    expect(page).to have_link(I18n.t("maint_core.entity_domains.index.clear_filters"), href: "#{base}?domain_id=#{academics.id}")
  end

  it "ignores an unknown kind" do
    render_workspace(selected: academics.id, kind: "bogus")

    expect(entity_ids).to contain_exactly(student.id, bridge.id)
  end

  it "shows unplaced shared entities without domain actions or journeys" do
    render_workspace(selected: "ungrouped")

    header = page.find("[data-role='domain-header']")
    expect(header).to have_css("h2", text: I18n.t("maint_core.entity_domains.workspace.not_in_domain"))
    expect(header).to have_text(I18n.t("maint_core.entity_domains.workspace.not_in_domain_hint"))
    expect(header).not_to have_link(I18n.t("maint_core.entities.index.new_entity"))
    expect(entity_ids).to eq([country.id])
    expect(page).to have_css(".badge", text: I18n.t("common.labels.shared"))
    expect(page).not_to have_css("[data-role='domain-journeys']")
  end

  it "says so when the chosen domain no longer exists" do
    render_workspace(selected: "999999")

    expect(page).to have_text(I18n.t("maint_core.entity_domains.index.domain_missing"))
    expect(page).not_to have_css("[data-role='domain-header']")
  end

  it "asks for a first domain outside the frame when the customer has none" do
    EntityDomain.where(customer_id: customer.id).destroy_all

    render_workspace

    empty = page.find("[data-role='no-domains']")
    expect(empty).to have_text(I18n.t("maint_core.entity_domains.workspace.no_domains_title"))
    expect(empty).to have_link(I18n.t("maint_core.entity_domains.index.new_domain"))
    expect(page).not_to have_css("turbo-frame")
  end

  it "offers edit and a move to another domain per entity" do
    render_workspace(selected: academics.id)

    row = page.find("[data-entity-id='#{student.id}']")
    expect(row).to have_link(I18n.t("common.actions.edit"), href: "#{base}/#{student.id}/edit")
    expect(row).to have_link(I18n.t("maint_core.entity_domains.index.move"),
                             href: "/#{customer.id}/admin/maintenance/entities/#{student.id}/domain_membership/edit",
                             visible: :all)
  end

  it "renders in zh-CN" do
    render_workspace(selected: academics.id, locale: :"zh-CN")

    expect(page).to have_text(I18n.t("maint_core.entities.index.new_entity", locale: :"zh-CN"))
    expect(page).to have_text(I18n.t("journeys.admin.title", locale: :"zh-CN"))
  end
end
