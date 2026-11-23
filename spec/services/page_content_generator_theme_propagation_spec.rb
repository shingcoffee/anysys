# frozen_string_literal: true

require "rails_helper"

# Task C coverage: theme propagation matrix, unknown-type fallbacks, and
# generate_content_only path.  These complement the developer-written inline
# specs and focus on cross-layer guarantees that are easy to regress.
RSpec.describe PageContentGenerator, "theme propagation and graceful degradation" do
  include PageRuntimeHelpers

  let_it_be(:customer) { create(:customer) }

  around { |example| Current.set(customer: nil, user: nil, shared_resources_mode: false) { example.run } }
  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  def make_page(fields:, theme: nil)
    config = {
      "pages"    => [{ "id" => "p1", "name" => "Test", "fields" => fields }],
      "fields"   => [],
      "settings" => {},
      "metadata" => {}
    }
    config["theme"] = theme if theme
    build_runtime_ui_page(config, customer: customer)
  end

  # ---------------------------------------------------------------------------
  # a. Theme propagation matrix — every LAYOUT_GENERATORS field_type passes theme:
  # ---------------------------------------------------------------------------

  describe "theme propagation matrix" do
    subject(:generated) { described_class.new(page_rec).generate }

    let(:all_layout_fields) do
      [
        { "id" => "f_section",      "field_type" => "section",      "property_type" => "layout", "label" => "My Section" },
        { "id" => "f_divider",      "field_type" => "divider",      "property_type" => "layout", "label" => "Divider" },
        { "id" => "f_heading",      "field_type" => "heading",      "property_type" => "layout", "label" => "Heading", "content" => "Title" },
        { "id" => "f_paragraph",    "field_type" => "paragraph",    "property_type" => "layout", "label" => "Para", "content" => "Body text" },
        { "id" => "f_spacer",       "field_type" => "spacer",       "property_type" => "layout", "spacer_height" => "md" },
        { "id" => "f_alert",        "field_type" => "alert",        "property_type" => "layout", "content" => "Warning", "alert_variant" => "warning" },
        { "id" => "f_image",        "field_type" => "image",        "property_type" => "layout", "image_url" => "https://example.com/img.png", "alt_text" => "img" },
        { "id" => "f_callout",      "field_type" => "callout",      "property_type" => "layout", "content" => "Note" },
        { "id" => "f_quote",        "field_type" => "quote",        "property_type" => "layout", "content" => "Quote text", "attribution" => "Author" },
        { "id" => "f_button",       "field_type" => "button",       "property_type" => "layout", "content" => "Click", "button_url" => "https://example.com" },
        { "id" => "f_video",        "field_type" => "video",        "property_type" => "layout", "video_url" => "https://www.youtube.com/watch?v=abc" },
        { "id" => "f_list",         "field_type" => "list",         "property_type" => "layout", "content" => "A\nB" },
        { "id" => "f_code_block",   "field_type" => "code_block",   "property_type" => "layout", "content" => "puts 'hi'" },
        { "id" => "f_card",         "field_type" => "card",         "property_type" => "layout", "label" => "Card", "content" => "Content" },
        { "id" => "f_progress_bar", "field_type" => "progress_bar", "property_type" => "layout", "label" => "Step", "progress_value" => 50 },
        { "id" => "f_columns",      "field_type" => "columns",      "property_type" => "layout", "column_layout" => "50-50",
          "columns" => [{ "fields" => [] }, { "fields" => [] }] }
      ]
    end

    let(:input_fields) do
      [
        { "id" => "i_text",   "property_slug" => "name",  "property_type" => "string", "html_type" => "text",   "label" => "Name" },
        { "id" => "i_email",  "property_slug" => "email", "property_type" => "email",  "html_type" => "email",  "label" => "Email" },
        { "id" => "i_select", "property_slug" => "role",  "property_type" => "select", "html_type" => "select", "label" => "Role" }
      ]
    end

    let(:theme) do
      { "primary_color" => "teal", "accent_color" => "teal", "font_family" => "sans",
        "border_radius" => "lg", "input_style" => "outline", "form_background" => "white" }
    end

    let(:page_rec) { make_page(fields: all_layout_fields + input_fields, theme: theme) }

    it "contains theme: in the generated ERB" do
      expect(generated).to include("theme:")
    end

    it "passes theme: to every layout element render call — count >= 16" do
      # Every layout element generator (16 total) emits via render_component_erb,
      # which always appends theme:. Plus the wrapper components (PageComponent,
      # FormComponent) and the input components also receive it.
      theme_occurrences = generated.scan("theme:").length
      expect(theme_occurrences).to be >= 16,
        "Expected >= 16 theme: occurrences (one per layout element), got #{theme_occurrences}"
    end

    it "always uses the unconditional || {} form for every theme: kwarg" do
      # Every occurrence should be the safe unconditional form, never a bare variable
      expect(generated).to include('@page.configuration_json["theme"] || {}')
    end

    it "mentions every layout-element component class exactly once" do
      %w[
        SectionElementComponent DividerElementComponent HeadingElementComponent
        ParagraphElementComponent SpacerElementComponent AlertElementComponent
        ImageElementComponent CalloutElementComponent QuoteElementComponent
        ButtonElementComponent VideoElementComponent ListElementComponent
        CodeBlockElementComponent CardElementComponent ProgressBarElementComponent
        ColumnsElementComponent
      ].each do |klass|
        expect(generated).to include(klass), "Expected generated ERB to include #{klass}"
      end
    end

    it "produces syntactically valid ERB (compiles without error)" do
      expect { ERB.new(generated) }.not_to raise_error
    end
  end

  # ---------------------------------------------------------------------------
  # b. Unknown html_type → TextFieldComponent fallback + comment
  # ---------------------------------------------------------------------------

  describe "unknown html_type graceful fallback" do
    subject(:generated) { described_class.new(page_rec).generate }

    let(:page_rec) do
      make_page(fields: [
        { "id" => "f_holo", "property_slug" => "holographic", "property_type" => "string",
          "html_type" => "holographic-input", "label" => "Holographic Field", "required" => true }
      ])
    end

    it "emits the fallback ERB comment identifying the field and the unknown type" do
      expect(generated).to include('<%# fallback: field "holographic" has unknown html_type "holographic-input" %>')
    end

    it "falls back to TextFieldComponent (not a silent skip)" do
      expect(generated).to include("FormFields::TextFieldComponent")
    end

    it "carries the field label in the fallback render call" do
      expect(generated).to include('label: "Holographic Field"')
    end

    it "produces syntactically valid ERB" do
      expect { ERB.new(generated) }.not_to raise_error
    end

    it "includes theme: in the fallback render call" do
      expect(generated).to include("theme:")
    end
  end

  describe "unknown html_type with injection-attempt payload" do
    let(:page_rec) do
      make_page(fields: [
        { "id" => "f_bad", "property_slug" => "evil", "property_type" => "string",
          "html_type" => 'bad"; rm -rf /', "label" => "Bad" }
      ])
    end

    it "sanitizes the html_type value in the fallback comment so it cannot inject code" do
      generated = described_class.new(page_rec).generate
      expect(generated).to include("FormFields::TextFieldComponent", '<%# fallback: field "evil"')
      expect(generated).not_to include('rm -rf /')
    end
  end

  # ---------------------------------------------------------------------------
  # c. Unknown layout field_type → skip comment, not empty string
  # ---------------------------------------------------------------------------

  describe "unknown layout field_type" do
    subject(:generated) { described_class.new(page_rec).generate }

    let(:page_rec) do
      make_page(fields: [
        { "id" => "f_before", "property_slug" => "name", "property_type" => "string", "html_type" => "text", "label" => "Name" },
        { "id" => "f_unk",    "field_type" => "hologram_widget", "property_type" => "layout", "label" => "Widget" },
        { "id" => "f_after",  "property_slug" => "email", "property_type" => "email", "html_type" => "email", "label" => "Email" }
      ])
    end

    it "emits the skip comment for the unknown field_type" do
      expect(generated).to include('<%# skipped layout element: unknown field_type "hologram_widget" %>')
    end

    it "does not emit an empty string for the unknown layout element" do
      # An empty string would cause the rendered template to silently drop
      # the element without any diagnostic hint for the page author.
      skip_comment = '<%# skipped layout element: unknown field_type "hologram_widget" %>'
      expect(generated).to include(skip_comment)
      # The surrounding known fields still render
      expect(generated).to include("TextFieldComponent")
      expect(generated).to include("EmailFieldComponent")
    end

    it "does not break surrounding valid fields" do
      expect(generated).to include('label: "Name"')
      expect(generated).to include('label: "Email"')
    end

    it "produces syntactically valid ERB" do
      expect { ERB.new(generated) }.not_to raise_error
    end

    it "sanitizes the unknown field_type slug in the comment" do
      # Injection attempt in field_type
      page_rec2 = make_page(fields: [
        { "id" => "f_x", "field_type" => 'evil"; rm -rf /', "property_type" => "layout", "label" => "X" }
      ])
      generated2 = described_class.new(page_rec2).generate
      expect(generated2).not_to include("rm -rf /")
      expect(generated2).to include("<%# skipped layout element:")
    end
  end

  # ---------------------------------------------------------------------------
  # f. generate_content_only with theme: {} still passes theme: to ContentComponent
  # ---------------------------------------------------------------------------

  describe "generate_content_only path" do
    # A page whose fields are ALL layout elements (no input fields) takes the
    # content-only branch; theme: must still be threaded through.

    let(:layout_only_fields) do
      [
        { "id" => "f_heading", "field_type" => "heading", "property_type" => "layout",
          "content" => "Content-only Heading" },
        { "id" => "f_para",    "field_type" => "paragraph", "property_type" => "layout",
          "content" => "Content-only body." }
      ]
    end

    context "when page theme is {} (empty)" do
      subject(:generated) { described_class.new(page_rec).generate }

      let(:page_rec) { make_page(fields: layout_only_fields, theme: {}) }

      it "takes the content-only branch (no FormComponent)" do
        expect(generated).to include("ContentComponent")
        expect(generated).not_to include("FormComponent")
      end

      it "passes theme: to ContentComponent" do
        expect(generated).to match(/ContentComponent\.new\(.*theme:/m)
      end

      it "uses the || {} fallback so ContentComponent never receives nil" do
        expect(generated).to include('@page.configuration_json["theme"] || {}')
      end
    end

    context "when page has no theme key at all" do
      subject(:generated) { described_class.new(page_rec).generate }
      let(:page_rec) { make_page(fields: layout_only_fields) }  # no theme key

      it "still passes theme: with || {} fallback to ContentComponent" do
        expect(generated).to include('@page.configuration_json["theme"] || {}')
      end

      it "produces syntactically valid ERB" do
        expect { ERB.new(generated) }.not_to raise_error
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Responsive width grid — breakpoint classes must be literal (Tailwind JIT)
  # ---------------------------------------------------------------------------

  describe "responsive field widths" do
    def text_field(id, width: nil, responsive_widths: nil)
      field = { "id" => id, "property_slug" => id, "property_type" => "string",
                "html_type" => "text", "label" => id.humanize }
      field["width"] = width if width
      field["responsive_widths"] = responsive_widths if responsive_widths
      field
    end

    it "collapses a half-width field to full on mobile, half from md up" do
      generated = described_class.new(make_page(fields: [text_field("a", width: "half"),
                                                         text_field("b", width: "half")])).generate
      expect(generated).to include("col-span-12 md:col-span-6")
    end

    it "honors an explicitly authored mobile width over the full-width default" do
      generated = described_class.new(make_page(fields: [
        text_field("a", width: "half", responsive_widths: { "mobile" => "half" }),
        text_field("b", width: "half", responsive_widths: { "mobile" => "half" })
      ])).generate
      expect(generated).to match(/class="[^"]*\bcol-span-6\b[^"]*"/)
      expect(generated).not_to include("md:col-span-6")
    end

    it "treats unknown width values as full rows (no grid, no col-span classes)" do
      generated = described_class.new(make_page(fields: [text_field("a", width: "bogus"),
                                                         text_field("b", width: "bogus")])).generate
      expect(generated).not_to include("col-span")
      expect(generated).to include('field_name: "a"')
      expect(generated).to include('field_name: "b"')
    end

    it "emits only literal breakpoint classes (no interpolation artifacts)" do
      generated = described_class.new(make_page(fields: [text_field("a", width: "third"),
                                                         text_field("b", width: "third")])).generate
      expect(generated).to include("md:col-span-4")
      expect(generated).not_to match(/md:#\{/)
    end
  end

  # ---------------------------------------------------------------------------
  # Columns element — per-column wrappers carry the resolved field spacing
  # ---------------------------------------------------------------------------

  describe "columns element internal spacing" do
    def columns_page(theme: nil)
      make_page(theme: theme, fields: [
        { "id" => "f_cols", "field_type" => "columns", "property_type" => "layout",
          "column_layout" => "50-50",
          "columns" => [
            { "fields" => [{ "id" => "c1", "property_slug" => "c1", "property_type" => "string", "html_type" => "text", "label" => "C1" }] },
            { "fields" => [{ "id" => "c2", "property_slug" => "c2", "property_type" => "string", "html_type" => "text", "label" => "C2" }] }
          ] }
      ])
    end

    it "applies the default field spacing to each column wrapper" do
      expect(described_class.new(columns_page).generate)
        .to match(/<div class="space-y-5">/)
    end

    it "applies the theme's relaxed field spacing to column wrappers" do
      generated = described_class.new(columns_page(theme: { "field_spacing" => "relaxed" })).generate
      expect(generated).to match(/<div class="space-y-8">/)
    end
  end
end
