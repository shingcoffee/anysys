# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityAssociationGraph do
  let_it_be(:customer) { create(:customer) }

  def make_entity(name, associations: [], bridge: false)
    create(:entity,
      customer: customer,
      name: name,
      category: (bridge ? :bridge : :plain),
      property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json,
      associations: associations.to_json
    )
  end

  it "primaries = entities that are never targets" do
    customer_entity = make_entity("Customer")
    order          = make_entity("Order")
    customer_entity.update!(associations: [{ "target_entity_id" => order.id, "display_field" => "name", "display_field_label" => "Name" }].to_json)

    graph = described_class.build(customer.id)

    expect(graph.primaries.map(&:name)).to contain_exactly("Customer")
    expect(graph.children_of(customer_entity).map(&:name)).to eq(["Order"])
    expect(graph.children_of(order)).to eq([])
  end

  it "excludes bridge entities from primaries and children" do
    primary = make_entity("Post")
    tag     = make_entity("Tag")
    bridge  = make_entity("PostTag", bridge: true)
    primary.update!(associations: [
      { "target_entity_id" => tag.id, "bridge_entity_id" => bridge.id, "display_field" => "name", "display_field_label" => "Name" }
    ].to_json)

    graph = described_class.build(customer.id)
    expect(graph.primaries.map(&:name)).to contain_exactly("Post")
    expect(graph.all_entities.map(&:name)).not_to include("PostTag")
    expect(graph.children_of(primary).map(&:name)).to eq(["Tag"])
  end

  it "standalone entity (no associations, not targeted) is its own primary" do
    lone = make_entity("Audit")
    graph = described_class.build(customer.id)
    expect(graph.primaries.map(&:name)).to include("Audit")
    expect(graph.children_of(lone)).to eq([])
  end

  it "includes shared entities so tenant entries on them appear in the data UI" do
    shared = create(:entity, :shared, name: "SharedContact")
    graph = described_class.build(customer.id)
    expect(graph.all_entities.map(&:name)).to include("SharedContact")
    expect(graph.primaries.map(&:id)).to include(shared.id)
  end

  it "keeps a rootless cycle reachable without discarding either relationship" do
    a = make_entity("CycleA")
    b = make_entity("CycleB")
    a.update!(associations: [{ "target_entity_id" => b.id, "display_field" => "name", "display_field_label" => "Name" }].to_json)
    b.update!(associations: [{ "target_entity_id" => a.id, "display_field" => "name", "display_field_label" => "Name" }].to_json)

    graph = described_class.build(customer.id)
    expect(graph.primaries.size).to eq(1)
    expect(graph.children_of(a).map(&:id)).to eq([b.id])
    expect(graph.children_of(b).map(&:id)).to eq([a.id])
  end

  it "adds a root for a disconnected cycle alongside ordinary roots" do
    root = make_entity("Root")
    a = make_entity("DetachedA")
    b = make_entity("DetachedB")
    a.update!(associations: [{ "target_entity_id" => b.id, "display_field" => "name", "display_field_label" => "Name" }].to_json)
    b.update!(associations: [{ "target_entity_id" => a.id, "display_field" => "name", "display_field_label" => "Name" }].to_json)

    graph = described_class.build(customer.id)
    expect(graph.primaries.map(&:id)).to include(root.id)
    expect(graph.primaries.size).to eq(2)
  end
end
