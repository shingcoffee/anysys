# frozen_string_literal: true

require "rails_helper"

RSpec.describe PermissionFilter do
  def node(key, permitted_by: nil, children: [])
    SidebarNode.new(
      key: key, label: key, menu_item: :settings,
      permitted_by: permitted_by, children: children
    )
  end

  let(:user)        { double(admin?: true,  owner?: false) }
  let(:member_user) { double(admin?: false, owner?: false) }

  it "keeps nodes with nil permitted_by" do
    tree = SidebarTree.new.add(node("always"))
    result = described_class.apply(tree, user)
    expect(result.nodes_for(:settings).map(&:key)).to eq(%w[always])
  end

  it "drops nodes whose permitted_by returns false" do
    tree = SidebarTree.new
    tree.add(node("admin_only", permitted_by: :admin?))
    tree.add(node("member_only", permitted_by: :member?))
    result = described_class.apply(tree, user)
    expect(result.nodes_for(:settings).map(&:key)).to eq(%w[admin_only])
  end

  it "recursively drops hidden children" do
    parent = node("parent", children: [
      node("a", permitted_by: :admin?),
      node("b", permitted_by: ->(_u) { false })
    ])
    tree = SidebarTree.new.add(parent)
    result = described_class.apply(tree, user)
    expect(result.nodes_for(:settings).first.children.map(&:key)).to eq(%w[a])
  end

  it "suppresses a parent whose children are all hidden and which has no own path" do
    parent = node("ghost", children: [node("x", permitted_by: ->(_u) { false })])
    tree = SidebarTree.new.add(parent)
    result = described_class.apply(tree, user)
    expect(result.nodes_for(:settings)).to be_empty
  end

  it "keeps a childless parent when its own permitted_by passes and it has a path" do
    leaf = SidebarNode.new(
      key: "x", label: "X", menu_item: :settings, path: "/x", permitted_by: nil
    )
    tree = SidebarTree.new.add(leaf)
    result = described_class.apply(tree, user)
    expect(result.nodes_for(:settings).map(&:key)).to eq(%w[x])
  end
end
