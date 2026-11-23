# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Domains", type: :request do
  include_context "as admin"

  let!(:entity) { create(:entity, customer: customer, name: "Student", display_label: "Student", description: "Enrolled learners") }
  let(:index_path) { admin_domains_path(customer.id) }
  let(:guard_path) { index_path }

  it_behaves_like "an admin-guarded GET"

  def body = Capybara.string(response.body)
  def stats = body.all("main dl[aria-label='Domain summary'] > div").map { |stat| [stat.find("dt").text.strip, stat.find("dd").text.strip] }

  def place(entity, domain, owner: customer)
    EntityDomainMembership.create!(customer: owner, entity_domain: domain, entity: entity)
  end

  it "renders the generic header with totals and the expanded sidebar, without cards, tabs or technical wording" do
    create(:entity_entry, customer: customer, entity: entity)
    get index_path

    expect(response).to have_http_status(:ok)
    expect(body).to have_css("main h1", text: "Domains")
    expect(stats).to eq([["Record types", "1"], ["Total entries", "1"], ["Pages", "0"], ["Last activity", "less than a minute ago"]])
    expect(body).not_to have_css("main li")
    expect(body).not_to have_css("main [data-section-nav-tab]")
    expect(body).not_to have_field(type: "search")
    expect(body).to have_css("#app-sidebar[data-state='expanded'][data-sidebar-collapsible-collapsed-value='false']")
    expect(body).to have_css("aside a[href='#{admin_entity_path(customer.id, entity)}']", text: entity.display_label)
    expect(body).not_to have_link("Create Entity")
    expect(body.find("main").text).not_to match(/entit/i)
    expect(body.find("#app-sidebar").text).not_to match(/entit/i)
  end

  it "expands the left sidebar by default even when a collapsed cookie was set earlier" do
    cookies["sidebar_state_entities"] = "collapsed"
    get index_path
    expect(body).to have_css("#app-sidebar[data-state='expanded'][data-sidebar-collapsible-collapsed-value='false']")
  end

  describe "with domains" do
    let!(:order) { create(:entity, customer: customer, name: "Order", display_label: "Order") }
    let!(:domain) { create(:entity_domain, customer: customer, name: "Academics", description: "Teaching and learning") }

    before { place(entity, domain) }

    def sidebar = body.find("#app-sidebar")

    it "shows only the first domain, expanded alone in a heading-less sidebar, read-only for a tenant admin" do
      get index_path

      expect(body.find("main h1")).to have_text("Academics")
      expect(body.find("main")).not_to have_link(order.display_label)

      groups = sidebar.all("details > summary").map { |summary| summary.text.squish }
      expect(groups).to eq(["Academics", "Other"])
      expect(sidebar).to have_css("details[open]", count: 1)
      expect(sidebar.find("details[open]")).to have_link("Academics", href: admin_domain_path(customer.id, domain.id))
      expect(sidebar.find("details[open]")).to have_link(entity.display_label, href: admin_entity_path(customer.id, entity))
      expect(sidebar).to have_css("a[aria-current='page']", text: "Academics")
      expect(sidebar).not_to have_link("Overview")
      expect(sidebar).not_to have_css("h3")
      expect(sidebar).not_to have_text("Business areas")

      expect(body).not_to have_link("Manage domains")
      expect(body).not_to have_link("New domain")
      expect(body).not_to have_css("a[href='#{edit_admin_maintenance_entity_domain_path(customer.id, domain)}']")
    end

    it "shows the clicked domain and expands only that domain in the sidebar" do
      get admin_domain_path(customer.id, "ungrouped")

      expect(response).to have_http_status(:ok)
      expect(body.find("main h1")).to have_text("Other")
      expect(stats.first).to eq(["Record types", "1"])
      expect(sidebar).to have_css("details[open]", count: 1)
      expect(sidebar.find("details[open]")).to have_link("Other", href: admin_domain_path(customer.id, "ungrouped"))
      expect(sidebar.find("details[open]")).to have_link(order.display_label)
      expect(sidebar).to have_css("a[aria-current='page']", text: "Other")
    end

    it "names the domain in the header over its totals, with no Record types / Pages tabs" do
      create(:page, customer: customer, entity: entity, name: "Enrolment")
      create(:page, customer: customer, entity: order, name: "Checkout")
      create_list(:entity_entry, 2, customer: customer, entity: entity)

      get admin_domain_path(customer.id, domain.id)

      expect(body.find("main h1")).to have_text("Academics")
      expect(body).to have_css("main p", text: "Teaching and learning")
      expect(body).to have_css("main nav a[href='#{index_path}']", text: "Domains")
      expect(stats).to eq([["Record types", "1"], ["Total entries", "2"], ["Pages", "1"], ["Last activity", "less than a minute ago"]])
      expect(response.body).to include("<title>Academics")
      expect(body).not_to have_css("[data-section-nav-tab]")
      expect(body).not_to have_css("main li")
      expect(response.body).not_to include(admin_domain_pages_path(customer.id, domain.id))
    end

    it "lists the domain's primary record type first in the sidebar as plain rows" do
      name_schema = [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json
      course = create(:entity, customer: customer, name: "Course", display_label: "Course", property_schema: name_schema)
      place(course, domain)
      entity.update!(associations: [{ "target_entity_id" => course.id, "display_field" => "name", "display_field_label" => "Name" }].to_json)
      create(:entity_entry, customer: customer, entity: course)

      get admin_domain_path(customer.id, domain.id)

      rows = sidebar.all("details[open] ul li a")
      expect(rows.map { |link| link.text.squish }).to eq(%w[Student Course])
      expect(rows.first[:href]).to eq(admin_entity_path(customer.id, entity))
      expect(sidebar.find("details[open] ul")).not_to have_css("[data-role='tile']")
    end

    it "offers no Journeys tab, even to the platform owner (journeys live under Maintenance / Entities)" do
      create(:journey, customer: customer, entity_domain: domain)
      sign_out admin
      sign_in find_or_create_platform_owner

      get admin_domain_path(customer.id, domain.id)

      expect(response).to have_http_status(:ok)
      expect(body).not_to have_css("a[data-section-nav-tab='journeys']")
      expect(response.body).not_to include("/admin/domains/#{domain.id}/journeys")
    end

    it "keeps the domain highlighted in the sidebar on its Pages list" do
      get admin_domain_pages_path(customer.id, domain.id)

      expect(response).to have_http_status(:ok)
      expect(sidebar).to have_css("a[aria-current='page']", text: "Academics")
    end

    it "returns 404 for a domain that is not the customer's" do
      foreign = create(:entity_domain, customer: create(:customer), name: "Foreign")
      get admin_domain_path(customer.id, foreign.id)
      expect(response).to have_http_status(:not_found)
    end
  end

  it "opens the domain holding the record type being browsed" do
    domain = create(:entity_domain, customer: customer, name: "Academics")
    place(entity, domain)
    get admin_entity_path(customer.id, entity)
    expect(body.find("#app-sidebar")).to have_css("details[open] a[aria-current='page']", text: entity.display_label)
  end

  it "renders the empty state when nothing is browsable" do
    entity.destroy!
    get index_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Nothing to browse yet")
    expect(body).not_to have_css("main dl")
    expect(body).not_to have_link("Create Entity")
  end

  it "counts shared entities beside the tenant's own and never another tenant's entities or domains" do
    shared = create(:entity, :shared, name: "SharedRoster", display_label: "Shared Roster")
    other_customer = create(:customer)
    other = create(:entity, customer: other_customer, name: "Foreign", display_label: "Foreign Roster")
    foreign_domain = create(:entity_domain, customer: other_customer, name: "Foreign Domain")
    place(shared, foreign_domain, owner: other_customer)

    get index_path

    expect(body).to have_css("aside a[href='#{admin_entity_path(customer.id, shared)}']", text: "Shared Roster")
    expect(stats.first).to eq(["Record types", "2"])
    expect(body).not_to have_text(other.display_label)
    expect(body).not_to have_text("Foreign Domain")
  end

  context "as the platform owner on a tenant URL" do
    let(:platform_owner) { find_or_create_platform_owner }

    before do
      sign_out admin
      sign_in platform_owner
    end

    it "offers no entity creation and no domain management" do
      domain = create(:entity_domain, customer: customer, name: "Academics")
      place(entity, domain)

      get index_path

      expect(response).to have_http_status(:ok)
      expect(body).not_to have_link("Create Entity")
      expect(body).not_to have_css("main a[href='#{new_admin_maintenance_entity_path(customer.id)}']")
      expect(body).not_to have_link("Manage domains")
      expect(body).not_to have_css("main a[href*='entity_domains']")
      expect(body).not_to have_css("main a[href='#{admin_maintenance_entities_path(customer.id)}']")
    end
  end
end
