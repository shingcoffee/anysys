# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccessPoints::Catalog do
  let_it_be(:customer) { create(:customer) }
  let(:fake_provider) do
    Class.new(AccessPoints::Provider) do
      def call(customer_id:)
        [
          AccessPoints::Descriptor.new(
            subject_type: "Route",
            subject_key:  "x/y",
            subject_id:   nil,
            actions:      [:read],
            group_key:    "g.one",
            label:        "X/Y",
            description:  nil
          )
        ]
      end

      def group_key   = "g.one"
      def group_label = "Group One"
    end.new
  end

  before { AccessPoints::Registry.reset!; Current.access_points_catalog = nil }
  after  { AccessPoints::Registry.install_default_providers!; Current.access_points_catalog = nil }

  it "merges provider output into groups keyed by group_key" do
    AccessPoints::Registry.register(fake_provider)
    catalog = described_class.for(customer_id: customer.id)
    group = catalog.groups.find { |g| g[:key] == "g.one" }
    expect(group[:descriptors].map(&:subject_key)).to eq(["x/y"])
  end

  it "uses Provider#label_for_group when a descriptor's group_key differs from the provider group_key" do
    split = Class.new(AccessPoints::Provider) do
      def call(customer_id:)
        [
          AccessPoints::Descriptor.new(
            subject_type: "Module",
            subject_key:  "payments",
            subject_id:   nil,
            actions:      [:manage],
            group_key:    "modules.payments",
            label:        "Payments",
            description:  nil
          )
        ]
      end

      def group_key   = "modules"
      def group_label = "Modules"

      def label_for_group(key)
        key == "modules.payments" ? "Localized Payments" : super
      end
    end.new

    AccessPoints::Registry.register(split)
    catalog = described_class.for(customer_id: customer.id)
    group = catalog.groups.find { |g| g[:key] == "modules.payments" }
    expect(group[:label]).to eq("Localized Payments")
  end

  it "skips non-applicable providers" do
    inactive = Class.new(AccessPoints::Provider) do
      def call(customer_id:) = raise("should not be called")
      def group_key = "skip"
      def group_label = "Skip"
      def applicable?(customer_id:) = false
    end.new

    AccessPoints::Registry.register(inactive)
    expect { described_class.for(customer_id: customer.id) }.not_to raise_error
  end

  describe "#find" do
    it "looks up a descriptor by subject_type + subject_key" do
      AccessPoints::Registry.register(fake_provider)
      catalog = described_class.for(customer_id: customer.id)
      d = catalog.find(subject_type: "Route", subject_key: "x/y")
      expect(d).not_to be_nil
    end
  end
end
