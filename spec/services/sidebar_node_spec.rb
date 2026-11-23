# frozen_string_literal: true

require "rails_helper"

RSpec.describe SidebarNode do
  # Builds a node with sensible defaults; pass keywords to override any of them.
  def node(**overrides)
    described_class.new(**{ key: "k", label: "L", menu_item: :entities }.merge(overrides))
  end

  describe "MENU_ITEMS constant" do
    it "includes all seven dashboard menu items" do
      expect(described_class::MENU_ITEMS).to eq(
        %i[home assistant entities pages modules settings maintenance]
      )
    end
  end

  describe ".new" do
    it "accepts menu_item keyword and exposes it" do
      expect(node(menu_item: :entities).menu_item).to eq(:entities)
    end

    it "raises when menu_item is not in MENU_ITEMS" do
      expect { node(menu_item: :unknown) }
        .to raise_error(ArgumentError, /menu_item/)
    end
  end

  describe "#with_children" do
    it "preserves menu_item on the copy" do
      child = node(key: "c", label: "C", menu_item: :entities)
      parent = node(key: "p", label: "P", menu_item: :entities)
      expect(parent.with_children([child]).menu_item).to eq(:entities)
    end

    it "preserves description on the copy" do
      child = node(key: "c", label: "C", menu_item: :entities)
      parent = node(key: "p", label: "P", menu_item: :entities, description: "About P")
      expect(parent.with_children([child]).description).to eq("About P")
    end

    it "preserves exact path aliases when permission filtering copies nodes" do
      parent = node(path: "/setting", match_paths: ["/setting", "/settings"])
      expect(parent.with_children([]).match_paths).to eq(["/setting", "/settings"])
      expect(node.match_paths).to eq([])
    end
  end

  describe "#link?" do
    it "returns true when path is present" do
      expect(node(path: "/x").link?).to be true
    end

    it "returns false when path is nil" do
      expect(node(path: nil).link?).to be false
    end

    it "returns false when path is empty" do
      expect(node(path: "").link?).to be false
    end
  end

  describe "#permitted_for?" do
    let(:user) { double(admin_or_owner?: true) }

    it "returns true when permitted_by is nil" do
      expect(node.permitted_for?(user)).to be true
    end

    it "calls a Symbol predicate on the user" do
      expect(node(menu_item: :modules, permitted_by: :admin_or_owner?).permitted_for?(user)).to be true
    end

    it "calls a Proc predicate with the user" do
      gate = ->(u) { u.admin_or_owner? }
      expect(node(permitted_by: gate).permitted_for?(double(admin_or_owner?: true))).to be true
      expect(node(permitted_by: gate).permitted_for?(double(admin_or_owner?: false))).to be false
    end

    it "returns false when the user does not respond to a Symbol predicate" do
      expect(node(permitted_by: :mystery?).permitted_for?(Object.new)).to be false
    end

    it "returns the user's predicate result when Symbol returns false" do
      expect(node(permitted_by: :admin_or_owner?).permitted_for?(double(admin_or_owner?: false))).to be false
    end
  end
end
