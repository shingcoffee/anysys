# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::CodeGenerators::IndexComponent, type: :component do
  let(:customer_id) { "81721200" }

  let(:sidebar_data) do
    [
      { kind: "element_type", key: "start",      label: "Start",      count: 3 },
      { kind: "element_type", key: "decision",   label: "Decision",   count: 2 },
      { kind: "element_type", key: "loop",       label: "Loop",       count: 1 },
      { kind: "element_type", key: "end",        label: "End",        count: 4 },
      { kind: "step_action",  key: "validation", label: "Validation", count: 5 }
    ]
  end

  let(:stub_generator_class) do
    Class.new do
      def self.name          = "CodeGenerators::Validation::CheckPresenceGenerator"
      def self._metadata     = { version: "1.0.0", description: "Validates field", category: :validation }
      def self.sample_input  = {}
      def self.generator_name = "check_presence"
      def self.generator_kind = :step_action
      def initialize(e, c); end
      def generate_body        = "ctx[:result] = true"
      def generate_step_method = "def call(ctx, **); end"
      def validate_config(_)   = []
      def dependencies         = []
    end
  end

  let(:filtered_generators) { { "check_presence" => stub_generator_class } }

  # Build a component with the shared defaults; any keyword overrides its default.
  def build_component(**opts)
    described_class.new(**{
      sidebar_data:        sidebar_data,
      filtered_generators: filtered_generators,
      customer_id:         customer_id
    }.merge(opts))
  end

  # ---------------------------------------------------------------------------
  # Composite: renders sub-components
  # ---------------------------------------------------------------------------
  describe "base rendering" do
    subject(:rendered) { render_inline(build_component(total_count: 10)) }

    it "renders the toolbar (Code Generators heading)" do
      expect(rendered.text).to include("Code Generators")
    end

    it "renders the sidebar nav" do
      expect(rendered.css("nav[data-controller='generator-search']")).not_to be_empty
    end

    it "renders the card grid" do
      expect(rendered.text).to include("check_presence")
    end
  end

  # ---------------------------------------------------------------------------
  # category_label branches
  # ---------------------------------------------------------------------------
  describe "#category_label" do
    it "uses element_type.titleize when element_type is given" do
      expect(build_component(element_type: "start").category_label).to eq("Start")
    end

    it "titleizes underscore-separated category when category is given" do
      expect(build_component(category: "model_operations").category_label).to eq("Model Operations")
    end

    it "falls back to the first sidebar_data label when neither is given" do
      expect(build_component.category_label).to eq("Start")
    end

    it "falls back to 'Code Generators' when sidebar_data is empty and no filter given" do
      expect(build_component(sidebar_data: []).category_label).to eq("Code Generators")
    end
  end

  # ---------------------------------------------------------------------------
  # category_icon branches
  # ---------------------------------------------------------------------------
  describe "#category_icon" do
    it "returns an icon path for a known element_type" do
      # start maps to SidebarComponent::STEP_ACTION_ICONS.values.first or ELEMENT_TYPE_DOTS fallback
      expect(build_component(element_type: "start").category_icon).not_to be_nil
    end

    it "returns an icon path for a known step_action category" do
      expect(build_component(category: "validation").category_icon).not_to be_nil
    end

    it "returns nil when neither element_type nor category is given" do
      expect(build_component.category_icon).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # category_count
  # ---------------------------------------------------------------------------
  describe "#category_count" do
    it "equals the size of filtered_generators" do
      expect(build_component.category_count).to eq(1)
    end

    it "is 0 when filtered_generators is empty" do
      expect(build_component(filtered_generators: {}).category_count).to eq(0)
    end
  end

  # ---------------------------------------------------------------------------
  # Empty generators renders empty state inside grid
  # ---------------------------------------------------------------------------
  it "renders empty state inside the card grid when filtered_generators is empty" do
    rendered = render_inline(build_component(filtered_generators: {}))
    expect(rendered.text).to include("No generators")
  end
end
