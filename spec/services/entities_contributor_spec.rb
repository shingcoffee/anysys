# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntitiesContributor do
  let(:customer) { Customer.create!(id: 12345678, name: "T", industry: :technology) }
  let(:context)  { DashboardContext.new(current_user: nil, current_customer: customer, current_menu_item: :entities, request_path: "/") }

  def nodes = described_class.new(context).contribute
  def path_for(entity) = "/#{customer.id}/admin/entities/#{entity.id}"

  def place(entity, domain)
    EntityDomainMembership.create!(customer: customer, entity_domain: domain, entity: entity)
  end

  it "emits nodes keyed to :entities menu_item" do
    Entity.create!(customer_id: customer.id, name: "Account", category: :plain)
    expect(nodes).not_to be_empty
    expect(nodes).to all(have_attributes(menu_item: :entities))
  end

  it "lists the entities flat, by label, with no heading while the customer has no domains, and no Overview link" do
    zebra = Entity.create!(customer_id: customer.id, name: "Zebra", display_label: "zebras", category: :plain)
    account = Entity.create!(customer_id: customer.id, name: "Account", display_label: "Accounts", category: :plain)

    expect(nodes).to all(have_attributes(category?: false))
    expect(nodes.map(&:key)).to eq(["entities.#{account.id}", "entities.#{zebra.id}"])
    expect(nodes.first).to have_attributes(label: "Accounts", path: path_for(account), match_prefix: path_for(account), children: [])
    expect(nodes.map(&:path)).not_to include("/#{customer.id}/admin/domains")
  end

  it "renders each entity as a plain row: no icon, monogram, tone or count" do
    Entity.create!(customer_id: customer.id, name: "Person", category: :plain, icon: "user", color: "rose")
    expect(nodes.first).to have_attributes(icon: nil, monogram: nil, tone: nil, badge: nil)
  end

  it "excludes bridge entities" do
    Entity.create!(customer_id: customer.id, name: "Bridge", category: :bridge)
    expect(nodes).to be_empty
  end

  it "returns an empty array when customer_id is blank" do
    empty_ctx = DashboardContext.new(current_user: nil, current_customer: nil, current_menu_item: :entities, request_path: "/")
    expect(described_class.new(empty_ctx).contribute).to eq([])
  end

  describe "with domains" do
    let!(:student) { Entity.create!(customer_id: customer.id, name: "Student", category: :plain) }
    let!(:course) { Entity.create!(customer_id: customer.id, name: "Course", category: :plain) }
    let!(:order) { Entity.create!(customer_id: customer.id, name: "Order", category: :plain) }
    let!(:loose) { Entity.create!(customer_id: customer.id, name: "Loose", category: :plain) }

    it "lists only domains, by name, with no heading, each linking to its page, with ungrouped entities under Other" do
      sales = create(:entity_domain, customer: customer, name: "Sales", color: "amber")
      academics = create(:entity_domain, customer: customer, name: "Academics", color: "blue")
      create(:entity_domain, customer: customer, name: "Empty")
      place(student, academics)
      place(course, academics)
      place(order, sales)
      foreign = create(:entity_domain, customer: create(:customer), name: "Foreign")
      EntityDomainMembership.create!(customer: foreign.customer, entity_domain: foreign, entity: loose)

      domains = nodes
      expect(domains).to all(have_attributes(category?: false))
      base = "/#{customer.id}/admin/domains"
      expect(domains.map(&:label)).to eq(%w[Academics Sales Other])
      expect(domains.map(&:key)).to eq(["entities.domain.#{academics.id}", "entities.domain.#{sales.id}", "entities.domain.ungrouped"])
      expect(domains.map(&:path)).to eq(["#{base}/#{academics.id}", "#{base}/#{sales.id}", "#{base}/ungrouped"])
      expect(domains.map(&:match_paths)).to eq([[base], [], []])
      expect(domains.map(&:match_prefix)).to eq(domains.map(&:path))
      expect(domains).to all(have_attributes(section_root: false))
      expect(domains.map(&:icon)).to eq(described_class::ICONS.values_at(:domain, :domain, :ungrouped))
      expect(domains.map(&:tone)).to eq(["domain.blue", "domain.amber", nil])
      expect(domains.map { |node| node.children.map(&:key) }).to eq([
        ["entities.#{course.id}", "entities.#{student.id}"],
        ["entities.#{order.id}"],
        ["entities.#{loose.id}"]
      ])
      expect(domains.first.children.first).to have_attributes(path: path_for(course), children: [])
    end

    it "adds a childless Other node for unbound forms once every entity sits in a domain" do
      domain = create(:entity_domain, customer: customer, name: "All")
      [student, course, order, loose].each { |entity| place(entity, domain) }
      expect(nodes.map(&:label)).to eq(["All"])

      orphan = create(:page, customer: customer, entity: student)
      orphan.entity_id = nil
      orphan.save!(validate: false)

      other = nodes.last
      expect(other).to have_attributes(key: "entities.domain.ungrouped", path: "/#{customer.id}/admin/domains/ungrouped",
                                       children: [])
    end

    it "lists a domain's entities primary first, the one declaring the most associations leading" do
      name_schema = [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json
      [course, order].each { |target| target.update!(property_schema: name_schema) }
      link = ->(target) { { "target_entity_id" => target.id, "display_field" => "name", "display_field_label" => "Name" } }
      student.update!(associations: [link.(course)].to_json)
      loose.update!(associations: [link.(course), link.(order)].to_json)
      academics = create(:entity_domain, customer: customer, name: "Academics")
      [student, course, order, loose].each { |entity| place(entity, academics) }

      children = nodes.find { |node| node.label == "Academics" }.children
      expect(children.map(&:key)).to eq(["entities.#{loose.id}", "entities.#{student.id}", "entities.#{course.id}", "entities.#{order.id}"])
    end

    it "lists an associated entity under its own domain rather than its parent's" do
      name_schema = [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json
      course.update!(property_schema: name_schema)
      student.update!(associations: [{ "target_entity_id" => course.id, "display_field" => "name", "display_field_label" => "Name" }].to_json)
      people = create(:entity_domain, customer: customer, name: "People")
      catalog = create(:entity_domain, customer: customer, name: "Catalog")
      place(student, people)
      place(course, catalog)

      grouped = nodes.to_h { |node| [node.label, node.children.map(&:key)] }
      expect(grouped["People"]).to eq(["entities.#{student.id}"])
      expect(grouped["Catalog"]).to eq(["entities.#{course.id}"])
    end
  end

  it "lists every entity of an association cycle once" do
    name_schema = [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json
    a = create(:entity, customer: customer, name: "CycleA", property_schema: name_schema)
    b = create(:entity, customer: customer, name: "CycleB", property_schema: name_schema)
    [[a, b], [b, a]].each do |source, target|
      source.update!(associations: [{ "target_entity_id" => target.id, "display_field" => "name", "display_field_label" => "Name" }].to_json)
    end
    expect(nodes.map(&:path)).to contain_exactly(path_for(a), path_for(b))
  end
end
