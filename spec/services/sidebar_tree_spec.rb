# frozen_string_literal: true

require "rails_helper"

RSpec.describe SidebarTree do
  let(:node) { SidebarNode.new(key: "e", label: "E", menu_item: :entities) }

  describe "#add and #nodes_for" do
    it "stores nodes under their menu_item" do
      tree = described_class.new
      tree.add(node)
      expect(tree.nodes_for(:entities)).to eq([node])
    end

    it "returns empty array for unknown menu_item" do
      expect(described_class.new.nodes_for(:unknown)).to eq([])
    end
  end

  describe "#replace" do
    it "replaces all nodes for a menu_item" do
      tree = described_class.new.add(node)
      other = SidebarNode.new(key: "e2", label: "E2", menu_item: :entities)
      tree.replace(:entities, [other])
      expect(tree.nodes_for(:entities)).to eq([other])
    end
  end
end
