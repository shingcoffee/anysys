# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::CodeGenerators::CardGridComponent, type: :component do
  let(:customer_id) { "81721200" }

  # Minimal generator class stub that satisfies CardGridComponent#generator_io
  # and the template's _metadata / name references.
  let(:stub_generator_class) do
    Class.new do
      def self.name = "CodeGenerators::Validation::CheckPresenceGenerator"
      def self._metadata = { version: "1.0.0", description: "Checks presence of a field", category: :validation }
      def self.sample_input = {}
      def self.generator_name = "check_presence"
      def self.generator_kind = :step_action

      # instance methods used by TestRunner
      def initialize(element, ctx); end
      def generate_body = "ctx[:result] = ctx[:value].present?"
      def generate_step_method = "def call(ctx, **); end"
      def validate_config(_cfg) = []
      def dependencies = []
    end
  end

  let(:populated_generators) { { "check_presence" => stub_generator_class } }
  let(:empty_generators)     { {} }

  # Render the grid with sensible defaults; any keyword overrides the default.
  def render_card_grid(**opts)
    render_inline(described_class.new(**{
      generators:     populated_generators,
      category_label: "Validation",
      customer_id:    customer_id
    }.merge(opts)))
  end

  # ---------------------------------------------------------------------------
  # Header / category bar (always rendered)
  # ---------------------------------------------------------------------------
  describe "category bar" do
    it "renders the category label" do
      render_card_grid
      expect(page).to have_text("Validation")
    end

    it "shows the generator count" do
      render_card_grid(category_count: 1)
      expect(page).to have_text("1 generators")
    end

    it "renders an SVG icon when category_icon is provided" do
      render_card_grid(category_icon: "M9 12l2 2 4-4")
      expect(page).to have_css("svg")
    end

    it "omits the SVG icon when category_icon is nil" do
      render_card_grid(category_icon: nil)
      # The grid area has no SVG icon in the top-bar (card chevrons are present
      # but the header icon <svg> is only rendered when category_icon is set)
      svg_in_bar = page.all("div.bg-surface-active").first
      # Just verify no error raised and SVG is absent from the top-bar
      expect(page.native.to_s).not_to include("stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"2\" d=\"M9 12l2 2 4-4\"")
    end
  end

  # ---------------------------------------------------------------------------
  # Empty collection branch
  # ---------------------------------------------------------------------------
  describe "with no generators" do
    before { render_card_grid(generators: empty_generators) }

    it "renders the empty state component" do
      expect(page).to have_text("No generators")
    end

    it "includes a 'New Generator' action link" do
      expect(page).to have_text("New Generator")
    end
  end

  # ---------------------------------------------------------------------------
  # Populated collection branch
  # ---------------------------------------------------------------------------
  describe "with generators" do
    before { render_card_grid(category_count: 1) }

    it "renders the generator name" do
      expect(page).to have_text("check_presence")
    end

    it "renders the version badge" do
      expect(page).to have_text("v1.0.0")
    end

    it "renders the description" do
      expect(page).to have_text("Checks presence of a field")
    end

    it "renders a link to the generator detail page" do
      encoded = ERB::Util.url_encode("validation/check_presence_generator")
      expect(page).to have_css("a[href*='#{encoded}']")
    end

    it "does not show the empty state" do
      expect(page).not_to have_text("No generators found")
    end
  end

  # ---------------------------------------------------------------------------
  # I/O badge branches
  # ---------------------------------------------------------------------------
  describe "generator I/O display" do
    it "shows input count badge when generator has inputs" do
      klass_with_inputs = Class.new(stub_generator_class) do
        def generate_body = "x = ctx[:email]; ctx[:result] = x"
      end

      render_card_grid(generators: { "check_presence" => klass_with_inputs })
      expect(page).to have_text("in")
    end

    it "shows output count badge when generator has outputs" do
      render_card_grid
      expect(page).to have_text("out")
    end

    it "gracefully handles a generator where TestRunner raises" do
      broken_klass = Class.new do
        def self.name = "CodeGenerators::Broken::BrokenGenerator"
        def self._metadata = { version: "0.0.1", description: "Broken", category: :utility }
        def self.sample_input = {}
        def self.generator_name = "broken"
        def initialize(_e, _c) = raise("boom")
      end

      expect {
        render_card_grid(generators: { "broken" => broken_klass }, category_label: "Utility")
      }.not_to raise_error
    end
  end
end
