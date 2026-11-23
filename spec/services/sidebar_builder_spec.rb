# frozen_string_literal: true

require "rails_helper"

RSpec.describe SidebarBuilder do
  let(:user) { double(admin_or_owner?: true, owner?: true) }
  let(:customer) { double(id: 12345678) }
  let(:context) do
    DashboardContext.new(
      current_user: user, current_customer: customer,
      current_menu_item: :entities, request_path: "/"
    )
  end

  it "returns an empty tree when no contributors emit anything" do
    stub_const("SidebarContributor", Class.new do
      def self.registry = []
    end)
    tree = described_class.build(context, menu_item: :entities)
    expect(tree.nodes_for(:entities)).to eq([])
  end

  it "filters emitted nodes by the provided menu_item" do
    contrib_class = Class.new do
      def initialize(_ctx); end
      def contribute
        [
          SidebarNode.new(key: "e1", label: "E1", menu_item: :entities),
          SidebarNode.new(key: "p1", label: "P1", menu_item: :pages)
        ]
      end
    end
    stub_const("SidebarContributor", Class.new do
      define_singleton_method(:registry) { [contrib_class] }
    end)
    tree = described_class.build(context, menu_item: :pages)
    expect(tree.nodes_for(:pages).map(&:key)).to eq(["p1"])
    expect(tree.nodes_for(:entities)).to eq([])
  end
end
