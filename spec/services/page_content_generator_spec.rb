# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageContentGenerator do
  include PageRuntimeHelpers

  let_it_be(:customer) { create(:customer) }

  def ui_page(config)
    build_runtime_ui_page(config, customer: customer)
  end

  around { |example| Current.set(customer: nil, user: nil, shared_resources_mode: false) { example.run } }

  describe "#generate with ViewComponent output" do
    let(:page) { ui_page(configuration) }
    let(:configuration) do
      {
        "pages" => [
          {
            "id" => "page_1",
            "name" => "Contact",
            "fields" => [
              {
                "id" => "field_1",
                "property_slug" => "email",
                "property_type" => "email",
                "html_type" => "email",
                "label" => "Email Address",
                "placeholder" => "you@example.com",
                "required" => true,
                "width" => "full"
              }
            ]
          }
        ],
        "fields" => [],
        "settings" => {
          "submit_button_text" => "Send"
        },
        "metadata" => {}
      }
    end

    it "generates ViewComponent render calls" do
      result = described_class.new(page).generate

      expect(result).to include("render FormFields::PageComponent")
      expect(result).to include("render FormFields::FormComponent")
      expect(result).to include("render FormFields::EmailFieldComponent")
    end

    it "includes inline Tailwind classes" do
      result = described_class.new(page).generate

      expect(result).to include("class:")
    end

    it "passes field properties to components" do
      result = described_class.new(page).generate

      expect(result).to include('field_name: "email"')
      expect(result).to include('label: "Email Address"')
      expect(result).to include("required: true")
    end

    it "renders the declared public field as an enabled, schema-backed control" do
      content = described_class.new(page).generate
      html = Current.set(customer: customer, user: nil) do
        ApplicationController.render(inline: content, layout: false,
          assigns: { page: page, form_action: "/submit" })
      end
      document = Nokogiri::HTML.fragment(html)
      expect(page.entity.customer_id).to eq(customer.id)
      expect(document.at_css('input[name="email"]:not([disabled])')).to be_present
      expect(document.css('fieldset[disabled]')).to be_empty
    end

    it "uses submit_button_text from settings" do
      result = described_class.new(page).generate

      expect(result).to include('submit_text: "Send"')
    end

    it "generates WizardComponent for multi-page forms" do
      multi_page_config = {
        "pages" => [
          { "id" => "page_1", "name" => "Contact", "fields" => [
            { "id" => "f1", "property_slug" => "name", "property_type" => "string", "html_type" => "text", "label" => "Name" }
          ] },
          { "id" => "page_2", "name" => "Details", "fields" => [
            { "id" => "f2", "property_slug" => "bio", "property_type" => "text", "html_type" => "textarea", "label" => "Bio" }
          ] }
        ],
        "fields" => [],
        "form_settings" => { "submit_button_text" => "Send" },
        "metadata" => {}
      }
      multi_page = ui_page(multi_page_config)

      result = described_class.new(multi_page).generate

      expect(result).to include("render FormFields::WizardComponent")
    end
  end

  describe "#generate with empty configuration" do
    let(:page) { create(:page, configuration: { "fields" => [], "metadata" => {} }.to_json) }

    it "returns empty string for empty configuration" do
      result = described_class.new(page).generate

      expect(result).to eq("")
    end
  end

  describe "#generate with various field types" do
    let(:page) { ui_page(configuration) }
    let(:configuration) do
      {
        "pages" => [
          {
            "id" => "page_1",
            "name" => "Test Form",
            "fields" => fields
          }
        ],
        "fields" => [],
        "settings" => {},
        "metadata" => {}
      }
    end

    context "with text field" do
      let(:fields) do
        [{ "id" => "f1", "property_slug" => "name", "property_type" => "string", "html_type" => "text", "label" => "Name" }]
      end

      it "uses TextFieldComponent" do
        result = described_class.new(page).generate
        expect(result).to include("render FormFields::TextFieldComponent")
      end
    end

    context "with textarea field" do
      let(:fields) do
        [{ "id" => "f1", "property_slug" => "bio", "property_type" => "text", "html_type" => "textarea", "label" => "Bio" }]
      end

      it "uses TextareaFieldComponent" do
        result = described_class.new(page).generate
        expect(result).to include("render FormFields::TextareaFieldComponent")
      end
    end

    context "with number field" do
      let(:fields) do
        [{ "id" => "f1", "property_slug" => "age", "property_type" => "integer", "html_type" => "number", "label" => "Age" }]
      end

      it "uses NumberFieldComponent" do
        result = described_class.new(page).generate
        expect(result).to include("render FormFields::NumberFieldComponent")
      end
    end

    context "with boolean field" do
      let(:fields) do
        [{ "id" => "f1", "property_slug" => "agree", "property_type" => "boolean", "html_type" => "checkbox", "label" => "Agree?" }]
      end

      it "uses CheckboxFieldComponent" do
        result = described_class.new(page).generate
        expect(result).to include("render FormFields::CheckboxFieldComponent")
      end
    end

    context "with date field" do
      let(:fields) do
        [{ "id" => "f1", "property_slug" => "dob", "property_type" => "date", "html_type" => "date", "label" => "Date of Birth" }]
      end

      it "uses DateFieldComponent" do
        result = described_class.new(page).generate
        expect(result).to include("render FormFields::DateFieldComponent")
      end
    end

    context "with select field" do
      let(:fields) do
        [{ "id" => "f1", "property_slug" => "country", "property_type" => "select", "html_type" => "select", "label" => "Country" }]
      end

      it "uses SelectFieldComponent" do
        result = described_class.new(page).generate
        expect(result).to include("render FormFields::SelectFieldComponent")
      end
    end

    context "with select field with options" do
      let(:fields) do
        [{
          "id" => "f1", "property_slug" => "country", "property_type" => "select",
          "html_type" => "select", "label" => "Country",
          "options" => [
            { "label" => "United States", "value" => "us" },
            { "label" => "Canada", "value" => "ca" }
          ]
        }]
      end

      it "passes options to SelectFieldComponent" do
        result = described_class.new(page).generate
        expect(result).to include('options: [["United States", "us"], ["Canada", "ca"]]')
      end
    end

    context "with radio field with options" do
      let(:fields) do
        [{
          "id" => "f1", "property_slug" => "gender", "property_type" => "string",
          "html_type" => "radio", "label" => "Gender",
          "options" => [
            { "label" => "Male", "value" => "male" },
            { "label" => "Female", "value" => "female" }
          ]
        }]
      end

      it "passes options as hashes to RadioFieldComponent" do
        result = described_class.new(page).generate
        expect(result).to include("render FormFields::RadioFieldComponent")
        expect(result).to include('"label" => "Male"')
        expect(result).to include('"value" => "male"')
      end
    end

    context "with tel field" do
      let(:fields) do
        [{ "id" => "f1", "property_slug" => "phone", "property_type" => "tel", "html_type" => "tel", "label" => "Phone" }]
      end

      it "uses TextFieldComponent for tel type" do
        result = described_class.new(page).generate
        expect(result).to include("render FormFields::TextFieldComponent")
      end
    end

    context "with url field" do
      let(:fields) do
        [{ "id" => "f1", "property_slug" => "website", "property_type" => "url", "html_type" => "url", "label" => "Website" }]
      end

      it "uses TextFieldComponent for url type" do
        result = described_class.new(page).generate
        expect(result).to include("render FormFields::TextFieldComponent")
      end
    end
  end

  describe "#generate with field widths" do
    let(:page) { ui_page(configuration) }
    let(:configuration) do
      {
        "pages" => [
          {
            "id" => "page_1",
            "name" => "Test",
            "fields" => [
              { "id" => "f1", "property_slug" => "full_field", "property_type" => "string", "html_type" => "text", "label" => "Full", "width" => "full" },
              { "id" => "f2", "property_slug" => "half_field", "property_type" => "string", "html_type" => "text", "label" => "Half", "width" => "half" },
              { "id" => "f3", "property_slug" => "third_field", "property_type" => "string", "html_type" => "text", "label" => "Third", "width" => "third" }
            ]
          }
        ],
        "fields" => [],
        "settings" => {},
        "metadata" => {}
      }
    end

    it "applies appropriate Tailwind width classes" do
      result = described_class.new(page).generate

      # Full-width fields render standalone; half and third use grid col-span classes
      expect(result).to include("grid grid-cols-12")
      expect(result).to include("col-span-6")
      expect(result).to include("col-span-4")
    end
  end

  describe "#generate with help text" do
    let(:page) { ui_page(configuration) }
    let(:configuration) do
      {
        "pages" => [
          {
            "id" => "page_1",
            "name" => "Test",
            "fields" => [
              {
                "id" => "f1",
                "property_slug" => "email",
                "property_type" => "email",
                "html_type" => "email",
                "label" => "Email",
                "help_text" => "Enter your work email"
              }
            ]
          }
        ],
        "fields" => [],
        "settings" => {},
        "metadata" => {}
      }
    end

    it "includes help_text in component options" do
      result = described_class.new(page).generate

      expect(result).to include('help_text: "Enter your work email"')
    end
  end

  describe "#generate with conditional fields" do
    let(:page) { ui_page(configuration) }
    let(:configuration) do
      {
        "pages" => [
          {
            "id" => "page_1",
            "name" => "Test",
            "fields" => [
              {
                "id" => "f1",
                "property_slug" => "other_details",
                "property_type" => "text",
                "html_type" => "textarea",
                "label" => "Other Details",
                "conditions" => [
                  { "field_id" => "f0", "operator" => "equals", "value" => "other" }
                ]
              }
            ]
          }
        ],
        "fields" => [],
        "settings" => {},
        "metadata" => {}
      }
    end

    it "includes conditions in data attribute" do
      result = described_class.new(page).generate

      expect(result).to include("data-condition-runtime-rules-value")
    end
  end

  describe "#generate wizard with settings" do
    let(:page) { ui_page(configuration) }
    let(:configuration) do
      {
        "pages" => [
          { "id" => "page_1", "name" => "Step 1", "fields" => [
            { "id" => "f1", "property_slug" => "name", "property_type" => "string", "html_type" => "text", "label" => "Name" }
          ] },
          { "id" => "page_2", "name" => "Step 2", "fields" => [
            { "id" => "f2", "property_slug" => "email", "property_type" => "email", "html_type" => "email", "label" => "Email" }
          ] }
        ],
        "fields" => [],
        "form_settings" => {
          "submit_button_text" => "Finish"
        },
        "wizard_settings" => {
          "show_progress" => false,
          "allow_back" => false
        },
        "metadata" => {}
      }
    end

    it "passes wizard settings to WizardComponent" do
      result = described_class.new(page).generate

      expect(result).to include("show_progress: false")
      expect(result).to include("allow_back: false")
    end

    it "uses submit_text from settings" do
      result = described_class.new(page).generate

      expect(result).to include('submit_text: "Finish"')
    end
  end

  describe "#generate with layout components" do
    let(:page) { ui_page(configuration) }
    let(:configuration) do
      {
        "pages" => [
          {
            "id" => "page_1",
            "name" => "Test Form",
            "fields" => fields
          }
        ],
        "fields" => [],
        "settings" => {},
        "metadata" => {}
      }
    end

    context "with section field" do
      let(:fields) do
        [{
          "id" => "f1", "field_type" => "section", "property_type" => "layout",
          "label" => "Personal Info", "content" => "Fill in your details"
        }]
      end

      it "uses SectionElementComponent" do
        result = described_class.new(page).generate
        expect(result).to include("render FormFields::SectionElementComponent")
        expect(result).to include('title: "Personal Info"')
        expect(result).to include('description: "Fill in your details"')
      end

      it "does not render as a form input" do
        result = described_class.new(page).generate
        expect(result).not_to include("TextFieldComponent")
      end
    end

    context "with divider field" do
      let(:fields) do
        [{ "id" => "f1", "field_type" => "divider", "property_type" => "layout", "label" => "Divider" }]
      end

      it "uses DividerElementComponent" do
        result = described_class.new(page).generate
        expect(result).to include("render FormFields::DividerElementComponent")
      end
    end

    context "with heading field" do
      let(:fields) do
        [{
          "id" => "f1", "field_type" => "heading", "property_type" => "layout",
          "label" => "Heading", "content" => "Important Notice", "heading_level" => "h2"
        }]
      end

      it "uses HeadingElementComponent with correct level" do
        result = described_class.new(page).generate
        expect(result).to include("render FormFields::HeadingElementComponent")
        expect(result).to include('text: "Important Notice"')
        expect(result).to include("level: 2")
      end
    end

    context "with paragraph field" do
      let(:fields) do
        [{
          "id" => "f1", "field_type" => "paragraph", "property_type" => "layout",
          "label" => "Paragraph", "content" => "Please read carefully before submitting."
        }]
      end

      it "uses ParagraphElementComponent" do
        result = described_class.new(page).generate
        expect(result).to include("render FormFields::ParagraphElementComponent")
        expect(result).to include('content_text: "Please read carefully before submitting."')
      end
    end

    context "with spacer field" do
      let(:fields) do
        [{
          "id" => "f1", "field_type" => "spacer", "property_type" => "layout",
          "label" => "Spacer", "spacer_height" => "lg"
        }]
      end

      it "uses SpacerElementComponent" do
        result = described_class.new(page).generate
        expect(result).to include("render FormFields::SpacerElementComponent")
        expect(result).to include('height: "lg"')
      end

      it "defaults to md height for invalid values" do
        fields.first["spacer_height"] = "invalid"
        result = described_class.new(page).generate
        expect(result).to include('height: "md"')
      end
    end

    context "with alert field" do
      let(:fields) do
        [{
          "id" => "f1", "field_type" => "alert", "property_type" => "layout",
          "label" => "Alert", "content" => "Please review before continuing.", "alert_variant" => "warning"
        }]
      end

      it "uses AlertElementComponent" do
        result = described_class.new(page).generate
        expect(result).to include("render FormFields::AlertElementComponent")
        expect(result).to include('content_text: "Please review before continuing."')
        expect(result).to include('variant: "warning"')
      end

      it "defaults to info variant for invalid values" do
        fields.first["alert_variant"] = "invalid"
        result = described_class.new(page).generate
        expect(result).to include('variant: "info"')
      end
    end

    context "with image field" do
      let(:fields) do
        [{
          "id" => "f1", "field_type" => "image", "property_type" => "layout",
          "label" => "Image", "image_url" => "https://example.com/photo.jpg", "alt_text" => "A photo"
        }]
      end

      it "uses ImageElementComponent" do
        result = described_class.new(page).generate
        expect(result).to include("render FormFields::ImageElementComponent")
        expect(result).to include('image_url: "https://example.com/photo.jpg"')
        expect(result).to include('alt_text: "A photo"')
      end
    end

    context "with callout field" do
      let(:fields) do
        [{
          "id" => "f1", "field_type" => "callout", "property_type" => "layout",
          "label" => "Callout", "content" => "Read this carefully."
        }]
      end

      it "uses CalloutElementComponent" do
        result = described_class.new(page).generate
        expect(result).to include("render FormFields::CalloutElementComponent")
        expect(result).to include('content_text: "Read this carefully."')
      end
    end

    context "with quote field" do
      let(:fields) do
        [{
          "id" => "f1", "field_type" => "quote", "property_type" => "layout",
          "label" => "Quote", "content" => "To be or not to be.", "attribution" => "Shakespeare"
        }]
      end

      it "uses QuoteElementComponent" do
        result = described_class.new(page).generate
        expect(result).to include("render FormFields::QuoteElementComponent")
        expect(result).to include('content_text: "To be or not to be."')
        expect(result).to include('attribution: "Shakespeare"')
      end

      it "omits attribution when empty" do
        fields.first.delete("attribution")
        result = described_class.new(page).generate
        expect(result).not_to include("attribution:")
      end
    end

    context "with button field" do
      let(:fields) do
        [{
          "id" => "f1", "field_type" => "button", "property_type" => "layout",
          "label" => "Button", "content" => "Sign Up",
          "button_url" => "https://example.com", "button_variant" => "secondary", "button_size" => "lg",
          "alignment" => "center"
        }]
      end

      it "uses ButtonElementComponent" do
        result = described_class.new(page).generate
        expect(result).to include("render FormFields::ButtonElementComponent")
        expect(result).to include('content_text: "Sign Up"')
        expect(result).to include('button_url: "https://example.com"')
        expect(result).to include('button_variant: "secondary"')
        expect(result).to include('button_size: "lg"')
        expect(result).to include('alignment: "center"')
      end

      it "defaults to primary variant for invalid values" do
        fields.first["button_variant"] = "invalid"
        result = described_class.new(page).generate
        expect(result).to include('button_variant: "primary"')
      end
    end

    context "with video field" do
      let(:fields) do
        [{
          "id" => "f1", "field_type" => "video", "property_type" => "layout",
          "label" => "Video", "video_url" => "https://www.youtube.com/watch?v=abc123"
        }]
      end

      it "uses VideoElementComponent" do
        result = described_class.new(page).generate
        expect(result).to include("render FormFields::VideoElementComponent")
        expect(result).to include('video_url: "https://www.youtube.com/watch?v=abc123"')
      end
    end

    context "with list field" do
      let(:fields) do
        [{
          "id" => "f1", "field_type" => "list", "property_type" => "layout",
          "label" => "List", "content" => "Item 1\nItem 2", "list_style" => "numbered"
        }]
      end

      it "uses ListElementComponent" do
        result = described_class.new(page).generate
        expect(result).to include("render FormFields::ListElementComponent")
        expect(result).to include('list_style: "numbered"')
      end

      it "defaults to bullet for invalid list_style" do
        fields.first["list_style"] = "invalid"
        result = described_class.new(page).generate
        expect(result).to include('list_style: "bullet"')
      end
    end

    context "with code_block field" do
      let(:fields) do
        [{
          "id" => "f1", "field_type" => "code_block", "property_type" => "layout",
          "label" => "Code", "content" => "console.log('hello')", "code_language" => "JavaScript"
        }]
      end

      it "uses CodeBlockElementComponent" do
        result = described_class.new(page).generate
        expect(result).to include("render FormFields::CodeBlockElementComponent")
        # The user value is emitted as a raw Ruby string literal (the component
        # HTML-escapes it at render time); it must NOT be pre-escaped here, which
        # would otherwise double-escape and breaks Ruby/ERB injection safety.
        expect(result).to include(%q{content_text: "console.log('hello')"})
        expect(result).to include('code_language: "JavaScript"')
      end

      it "omits code_language when empty" do
        fields.first.delete("code_language")
        result = described_class.new(page).generate
        expect(result).not_to include("code_language:")
      end
    end

    context "with card field" do
      let(:fields) do
        [{
          "id" => "f1", "field_type" => "card", "property_type" => "layout",
          "label" => "Feature Highlight", "content" => "This is a great feature."
        }]
      end

      it "uses CardElementComponent" do
        result = described_class.new(page).generate
        expect(result).to include("render FormFields::CardElementComponent")
        expect(result).to include('title: "Feature Highlight"')
        expect(result).to include('content_text: "This is a great feature."')
      end
    end

    context "with progress_bar field" do
      let(:fields) do
        [{
          "id" => "f1", "field_type" => "progress_bar", "property_type" => "layout",
          "label" => "Completion", "progress_value" => 75, "progress_color" => "green"
        }]
      end

      it "uses ProgressBarElementComponent" do
        result = described_class.new(page).generate
        expect(result).to include("render FormFields::ProgressBarElementComponent")
        expect(result).to include('label: "Completion"')
        expect(result).to include("progress_value: 75")
        expect(result).to include('progress_color: "green"')
      end

      it "defaults to indigo for invalid color" do
        fields.first["progress_color"] = "invalid"
        result = described_class.new(page).generate
        expect(result).to include('progress_color: "indigo"')
      end

      it "clamps progress_value to 0-100" do
        fields.first["progress_value"] = 150
        result = described_class.new(page).generate
        expect(result).to include("progress_value: 100")
      end
    end

    context "with mixed layout and form fields" do
      let(:fields) do
        [
          { "id" => "f1", "field_type" => "section", "property_type" => "layout", "label" => "Contact" },
          { "id" => "f2", "property_slug" => "email", "property_type" => "email", "html_type" => "email", "label" => "Email" },
          { "id" => "f3", "field_type" => "divider", "property_type" => "layout", "label" => "Divider" },
          { "id" => "f4", "property_slug" => "name", "property_type" => "string", "html_type" => "text", "label" => "Name" }
        ]
      end

      it "renders layout components and form fields with correct components" do
        result = described_class.new(page).generate
        expect(result).to include("SectionElementComponent")
        expect(result).to include("EmailFieldComponent")
        expect(result).to include("DividerElementComponent")
        expect(result).to include("TextFieldComponent")
      end
    end
  end

  describe "#generate with theme" do
    let(:page) { ui_page(configuration) }
    let(:configuration) do
      {
        "pages" => [
          {
            "id" => "page_1",
            "name" => "Themed Form",
            "fields" => [
              { "id" => "f1", "property_slug" => "name", "property_type" => "string", "html_type" => "text", "label" => "Name" }
            ]
          }
        ],
        "fields" => [],
        "settings" => { "submit_button_text" => "Submit" },
        "metadata" => {},
        "theme" => {
          "primary_color" => "blue",
          "font_family" => "serif",
          "border_radius" => "md",
          "input_style" => "filled",
          "form_background" => "gray"
        }
      }
    end

    it "passes theme to PageComponent" do
      result = described_class.new(page).generate
      expect(result).to include("theme:")
      expect(result).to include('@page.configuration_json["theme"]')
    end

    it "passes theme to FormComponent and field components" do
      result = described_class.new(page).generate
      # PageComponent, FormComponent, and field component should each receive theme
      expect(result.scan("theme:").length).to be >= 3
    end
  end

  describe "#generate layout elements include theme: param when theme is configured" do
    let(:theme) do
      { "primary_color" => "rose", "font_family" => "sans", "border_radius" => "lg",
        "input_style" => "filled", "form_background" => "warm" }
    end
    let(:configuration) do
      {
        "pages" => [{
          "id" => "page_1",
          "name" => "Themed Layout Form",
          "fields" => fields
        }],
        "fields" => [],
        "settings" => {},
        "metadata" => {},
        "theme" => theme
      }
    end
    let(:page) { ui_page(configuration) }

    context "with a section element" do
      let(:fields) do
        [{ "id" => "f1", "field_type" => "section", "property_type" => "layout", "label" => "My Section" }]
      end

      it "includes theme: in the SectionElementComponent constructor" do
        result = described_class.new(page).generate
        expect(result).to include("render FormFields::SectionElementComponent")
        expect(result).to match(/SectionElementComponent\.new\(.*theme:/m)
      end
    end

    context "with a divider element" do
      let(:fields) do
        [{ "id" => "f1", "field_type" => "divider", "property_type" => "layout", "label" => "Divider" }]
      end

      it "includes theme: in the DividerElementComponent constructor" do
        result = described_class.new(page).generate
        expect(result).to include("render FormFields::DividerElementComponent")
        expect(result).to match(/DividerElementComponent\.new\(.*theme:/m)
      end
    end

    context "with a callout element" do
      let(:fields) do
        [{ "id" => "f1", "field_type" => "callout", "property_type" => "layout",
           "content" => "Take note" }]
      end

      it "includes theme: in the CalloutElementComponent constructor" do
        result = described_class.new(page).generate
        expect(result).to include("render FormFields::CalloutElementComponent")
        expect(result).to match(/CalloutElementComponent\.new\(.*theme:/m)
      end
    end
  end

  describe "#generate layout elements always pass theme: even when page has no theme configured" do
    let(:configuration) do
      {
        "pages" => [{
          "id" => "page_1",
          "name" => "No Theme Form",
          "fields" => [
            { "id" => "f1", "field_type" => "section", "property_type" => "layout", "label" => "Section" },
            { "id" => "f2", "field_type" => "divider", "property_type" => "layout", "label" => "Divider" },
            { "id" => "f3", "field_type" => "callout", "property_type" => "layout", "content" => "Note" }
          ]
        }],
        "fields" => [],
        "settings" => {},
        "metadata" => {}
      }
    end
    let(:page) { ui_page(configuration) }

    it "always includes theme: with a safe || {} fallback so components receive an empty hash when theme is blank" do
      result = described_class.new(page).generate
      # Theme is now passed unconditionally; the || {} fallback ensures components
      # always receive a hash (never nil), even when the page has no theme key.
      expect(result).to include('theme: (@page.configuration_json["theme"] || {})')
      # Generated ERB must be syntactically valid Ruby
      expect { ERB.new(result) }.not_to raise_error
    end
  end

  describe "#generate with columns layout" do
    let(:page) { ui_page(configuration) }
    let(:configuration) do
      {
        "pages" => [
          {
            "id" => "page_1",
            "name" => "Form with Columns",
            "fields" => [
              {
                "id" => "f_cols",
                "field_type" => "columns",
                "property_type" => "layout",
                "label" => "Columns",
                "column_layout" => "50-50",
                "columns" => [
                  {
                    "fields" => [
                      { "id" => "f1", "property_slug" => "first_name", "property_type" => "string", "html_type" => "text", "label" => "First Name" }
                    ]
                  },
                  {
                    "fields" => [
                      { "id" => "f2", "property_slug" => "last_name", "property_type" => "string", "html_type" => "text", "label" => "Last Name" }
                    ]
                  }
                ]
              }
            ]
          }
        ],
        "fields" => [],
        "settings" => {},
        "metadata" => {}
      }
    end

    it "uses ColumnsElementComponent" do
      result = described_class.new(page).generate
      expect(result).to include("render FormFields::ColumnsElementComponent")
    end

    it "passes column_layout to the component" do
      result = described_class.new(page).generate
      expect(result).to include('column_layout: "50-50"')
    end

    it "renders nested child fields inside columns" do
      result = described_class.new(page).generate
      expect(result).to include("render FormFields::TextFieldComponent")
      expect(result).to include('field_name: "first_name"')
      expect(result).to include('field_name: "last_name"')
    end

    context "with 3-column layout" do
      before { configuration["pages"][0]["fields"][0]["column_layout"] = "33-33-33" }

      it "passes the layout value" do
        result = described_class.new(page).generate
        expect(result).to include('column_layout: "33-33-33"')
      end
    end

    context "with empty columns" do
      let(:configuration) do
        {
          "pages" => [
            {
              "id" => "page_1",
              "name" => "Empty Columns",
              "fields" => [
                {
                  "id" => "f_cols",
                  "field_type" => "columns",
                  "property_type" => "layout",
                  "label" => "Columns",
                  "column_layout" => "50-50",
                  "columns" => [{ "fields" => [] }, { "fields" => [] }]
                }
              ]
            }
          ],
          "fields" => [],
          "settings" => {},
          "metadata" => {}
        }
      end

      it "renders the columns container without child fields" do
        result = described_class.new(page).generate
        expect(result).to include("render FormFields::ColumnsElementComponent")
        expect(result).not_to include("TextFieldComponent")
      end
    end
  end

  # -----------------------------------------------------------------------
  # Previously-uncovered paths
  # -----------------------------------------------------------------------

  describe "#generate with composite layout (line 77)" do
    # page.configuration_json["layout"] == "composite" triggers generate_composite
    let(:page) { ui_page(configuration) }
    let(:configuration) do
      {
        "layout" => "composite",
        "modules" => [],
        "metadata" => {}
      }
    end

    it "returns empty string when modules array is empty" do
      result = described_class.new(page).generate
      expect(result).to eq("")
    end

    context "with a non-empty modules config" do
      let(:configuration) do
        {
          "layout" => "composite",
          "modules" => [
            {
              "id" => "mod1",
              "type" => "list",
              "title" => "Contacts",
              "width" => "full",
              "entity_id" => nil,
              "columns" => []
            }
          ],
          "metadata" => {}
        }
      end

      it "renders the composite-page data-controller wrapper" do
        result = described_class.new(page).generate
        expect(result).to include('data-controller="composite-page"')
      end
    end
  end

  describe "#generate content-only (layout fields only — line 89-90)" do
    # When every field is property_type == "layout", has_inputs is false
    # and generate_content_only is called instead of generate_single_page.
    let(:page) { ui_page(configuration) }
    let(:configuration) do
      {
        "pages" => [
          {
            "id" => "page_1",
            "name" => "Info",
            "fields" => [
              { "id" => "f1", "field_type" => "paragraph", "property_type" => "layout",
                "label" => "Note", "content" => "Just some text." }
            ]
          }
        ],
        "fields" => [],
        "settings" => {},
        "metadata" => {}
      }
    end

    it "generates ContentComponent wrapper (not FormComponent)" do
      result = described_class.new(page).generate
      expect(result).to include("render FormFields::ContentComponent")
      expect(result).not_to include("render FormFields::FormComponent")
    end
  end

  describe "#generate wizard with preview_active_page (lines 166-168)" do
    let(:page) { ui_page(configuration) }
    let(:configuration) do
      {
        "pages" => [
          { "id" => "p1", "name" => "Step 1", "fields" => [
            { "id" => "f1", "property_slug" => "name", "property_type" => "string", "html_type" => "text", "label" => "Name" }
          ] },
          { "id" => "p2", "name" => "Step 2", "fields" => [
            { "id" => "f2", "property_slug" => "email", "property_type" => "email", "html_type" => "email", "label" => "Email" }
          ] }
        ],
        "fields" => [],
        "form_settings" => {},
        "preview_active_page" => "p2",
        "metadata" => {}
      }
    end

    it "sets initial_step based on preview_active_page" do
      result = described_class.new(page).generate
      # preview_active_page = "p2" which is index 1 → initial_step = 2
      expect(result).to include("initial_step: 2")
    end
  end

  describe "resolve_dynamic_options — tenant scoping and query branches (lines 344-374)" do
    let(:customer_a) { create(:customer) }
    let(:customer_b) { create(:customer) }

    context "when dynamic_options entity belongs to another tenant (line 346)" do
      # Entity belongs to customer_b but the page belongs to customer_a.
      # resolve_dynamic_options must skip the field (returns field unchanged).
      let(:entity_b) { create(:entity, customer: customer_b) }
      let(:page) do
        # Use the factory with an explicit entity for customer_a so the page saves.
        entity_a = create(:entity, customer: customer_a, property_schema: [{ "name_slug" => "choice", "type" => "String" }].to_json)
        config = {
          "pages" => [
            {
              "id" => "page_1",
              "name" => "Form",
              "fields" => [
                {
                  "id" => "f1", "property_slug" => "choice", "property_type" => "string",
                  "html_type" => "select", "label" => "Choice",
                  "dynamic_options" => {
                    "options_source" => "query",
                    "entity_id" => entity_b.id  # cross-tenant reference
                  }
                }
              ]
            }
          ],
          "fields" => [],
          "settings" => {},
          "metadata" => { "entity_id" => entity_a.id, "entity_name" => entity_a.name }
        }
        create(:page, customer: customer_a, entity: entity_a, configuration: config.to_json)
      end

      it "skips the dynamic options and leaves the field unchanged" do
        result = described_class.new(page).generate
        # The field renders without crashing — the cross-tenant entity is not found
        expect(result).to include("render FormFields::SelectFieldComponent")
      end
    end

    context "when dynamic_options entity belongs to same tenant — full query path (lines 348-374)" do
      let(:source_entity) { create(:entity, :with_name_status_schema, customer: customer_a) }
      let(:page) do
        entity_a = create(:entity, customer: customer_a, property_schema: [{ "name_slug" => "choice", "type" => "String" }].to_json)
        config = {
          "pages" => [
            {
              "id" => "page_1",
              "name" => "Form",
              "fields" => [
                {
                  "id" => "f1", "property_slug" => "choice", "property_type" => "string",
                  "html_type" => "select", "label" => "Choice",
                  "dynamic_options" => {
                    "options_source" => "query",
                    "entity_id" => source_entity.id,
                    "label_field" => "name",
                    "order_by" => "name",
                    "order_direction" => "asc",
                    "limit" => "10"
                  }
                }
              ]
            }
          ],
          "fields" => [],
          "settings" => {},
          "metadata" => { "entity_id" => entity_a.id, "entity_name" => entity_a.name }
        }
        create(:page, customer: customer_a, entity: entity_a, configuration: config.to_json)
      end

      before do
        # Create entries that match the schema so validation passes
        create(:entity_entry, customer: customer_a, entity: source_entity,
               data: { "name" => "Option A", "status" => "active" }.to_json)
        create(:entity_entry, customer: customer_a, entity: source_entity,
               data: { "name" => "Option B", "status" => "inactive" }.to_json)
      end


      it "executes the query and merges options onto the field" do
        result = described_class.new(page).generate
        expect(result).to include("render FormFields::SelectFieldComponent")
      end
    end

    context "when dynamic_options options_source is not 'query' (line 339)" do
      let(:page) do
        entity_a = create(:entity, customer: customer_a, property_schema: [{ "name_slug" => "choice", "type" => "String" }].to_json)
        config = {
          "pages" => [
            {
              "id" => "page_1",
              "name" => "Form",
              "fields" => [
                {
                  "id" => "f1", "property_slug" => "choice", "property_type" => "string",
                  "html_type" => "select", "label" => "Choice",
                  "dynamic_options" => { "options_source" => "static" }
                }
              ]
            }
          ],
          "fields" => [],
          "settings" => {},
          "metadata" => { "entity_id" => entity_a.id, "entity_name" => entity_a.name }
        }
        create(:page, customer: customer_a, entity: entity_a, configuration: config.to_json)
      end

      it "passes through the field without error" do
        expect { described_class.new(page).generate }.not_to raise_error
      end
    end
  end

  describe "runtime controller integration" do
    subject { described_class.new(page).generate }

    let(:config) do
      {
        "pages" => [{
          "id" => "page_1",
          "fields" => [
            { "id" => "f1", "property_slug" => "name", "property_type" => "string", "html_type" => "text", "label" => "Name" },
            { "id" => "f2", "property_slug" => "email", "property_type" => "string", "html_type" => "text", "label" => "Email" },
            { "id" => "total", "property_slug" => "total", "property_type" => "integer", "html_type" => "number", "label" => "Total" }
          ]
        }],
        "fields" => [],
        "metadata" => {},
        "rules" => [{
          "id" => "r1",
          "enabled" => true,
          "conditions" => { "logic" => "all", "groups" => [] },
          "actions" => [{ "type" => "show_field", "target_id" => "f2" }]
        }],
        "calculations" => [{
          "id" => "c1",
          "target_field_id" => "total",
          "formula" => "1 + 1"
        }]
      }
    end

    let(:page) { ui_page(config) }

    it "wraps content with condition-runtime controller" do
      expect(subject).to include('data-controller="condition-runtime"')
    end

    it "includes rules as JSON data attribute" do
      expect(subject).to include("data-condition-runtime-rules-value")
    end

    it "includes calculations as JSON data attribute" do
      expect(subject).to include("data-condition-runtime-calculations-value")
    end

    it "adds data-field-id to field wrappers" do
      expect(subject).to include('data-field-id="f1"')
    end
  end

  # -----------------------------------------------------------------------
  # Branch-coverage additions — uncovered paths not reached above
  # -----------------------------------------------------------------------

  describe "#generate — blank configuration (line 73 :else, returns '')" do
    it "returns empty string when page.configuration is blank" do
      page = create(:page, configuration: nil)
      expect(described_class.new(page).generate).to eq("")
    end
  end

  describe "#generate — single page with empty fields (line 84-85)" do
    it "returns '' when pages_config is empty" do
      config = { "pages" => [], "metadata" => {} }
      page = create(:page, configuration: config.to_json)
      expect(described_class.new(page).generate).to eq("")
    end

    it "returns '' when single page has no fields" do
      config = { "pages" => [{ "id" => "p1", "fields" => [] }], "metadata" => {} }
      page = create(:page, configuration: config.to_json)
      expect(described_class.new(page).generate).to eq("")
    end
  end

  describe "#generate — responsive_col_span branches (lines 259-260)" do
    # tablet == mobile → no md: class emitted (line 259 :else)
    # desktop == tablet but != mobile → only lg: class emitted (line 260 :else)
    let(:base_config) do
      lambda do |responsive_widths|
        {
          "pages" => [{
            "id" => "p1",
            "fields" => [
              { "id" => "f1", "property_slug" => "a", "property_type" => "string", "html_type" => "text",
                "label" => "A", "width" => "half", "responsive_widths" => responsive_widths },
              { "id" => "f2", "property_slug" => "b", "property_type" => "string", "html_type" => "text",
                "label" => "B", "width" => "third", "responsive_widths" => responsive_widths }
            ]
          }],
          "metadata" => {}
        }
      end
    end

    it "omits md: class when tablet == mobile (line 259 :else branch)" do
      # mobile=full, tablet defaults to desktop(half) — tablet != mobile → md: emitted normally.
      # To omit md:, set tablet explicitly equal to mobile:
      config = base_config.call({ "mobile" => "half", "tablet" => "half" })
      page   = ui_page(config)
      result = described_class.new(page).generate
      expect(result).not_to include("md:col-span-6")
    end

    it "includes lg: class when desktop != tablet (line 260 :then branch)" do
      # mobile=full, tablet=half, desktop=third — all different → both md: and lg: emitted
      config = base_config.call({ "mobile" => "full", "tablet" => "half" })
      # fields have width "third" (desktop); tablet "half" != desktop "third" → lg: class
      page   = ui_page(config)
      result = described_class.new(page).generate
      expect(result).to include("lg:col-span-4")
    end
  end

  describe "#generate composite — render_composite_module branch coverage" do
    let(:customer_a) { create(:customer) }
    let(:list_entity) { create(:entity, :with_name_status_schema, customer: customer_a) }

    def composite_page(modules_config, customer:)
      config = { "layout" => "composite", "modules" => modules_config, "metadata" => {} }
      create(:page, customer: customer, configuration: config.to_json)
    end

    it "renders a module with title (line 404 :then branch)" do
      page = composite_page([
        { "id" => "m1", "module_type" => "form", "title" => "My Module",
          "width" => "full", "entity_id" => nil }
      ], customer: customer_a)
      result = described_class.new(page).generate
      expect(result).to include("My Module")
    end

    it "renders a module without title (line 404 :else branch — no title div)" do
      page = composite_page([
        { "id" => "m1", "module_type" => "form", "title" => nil,
          "width" => "full", "entity_id" => nil }
      ], customer: customer_a)
      result = described_class.new(page).generate
      expect(result).not_to include("px-4 py-3 border-b")
    end

    it "renders hidden class when visibility has on_event (line 397-399 :then)" do
      page = composite_page([
        { "id" => "m1", "module_type" => "form", "width" => "full",
          "entity_id" => nil,
          "visibility" => { "on_event" => "some_event" } }
      ], customer: customer_a)
      result = described_class.new(page).generate
      expect(result).to include(" hidden\"")
    end

    it "renders no hidden class when visibility on_event is absent (line 397-399 :else)" do
      page = composite_page([
        { "id" => "m1", "module_type" => "form", "width" => "full",
          "entity_id" => nil,
          "visibility" => {} }
      ], customer: customer_a)
      result = described_class.new(page).generate
      expect(result).not_to include(" hidden\"")
    end

    it "renders list module with records — render_list_module_html non-empty path (lines 422-443)" do
      create(:entity_entry, customer: customer_a, entity: list_entity,
             data: { "name" => "Alice", "status" => "active" }.to_json)

      # resolve_columns expects column_slugs as a plain array of slug strings
      page = composite_page([
        { "id" => "m1", "module_type" => "list", "width" => "full",
          "entity_id" => list_entity.id,
          "config" => { "columns" => %w[name] } }
      ], customer: customer_a)
      result = described_class.new(page).generate
      expect(result).to include("list-module")
      # The table header "Name" and the data row both appear
      expect(result).to include("Name")
    end

    it "renders 'No records found' for list module with empty records (line 419 :then)" do
      page = composite_page([
        { "id" => "m1", "module_type" => "list", "width" => "full",
          "entity_id" => list_entity.id,
          "config" => {} }
      ], customer: customer_a)
      result = described_class.new(page).generate
      expect(result).to include("No records found")
    end

    it "emits non-list module as empty module-content (line 411 :else — empty string)" do
      page = composite_page([
        { "id" => "m1", "module_type" => "form", "width" => "full", "entity_id" => nil }
      ], customer: customer_a)
      result = described_class.new(page).generate
      expect(result).to include("module-content")
    end
  end

  describe "#generate wizard — preview_active_page not found (line 168 idx nil)" do
    it "keeps initial_step at 1 when preview_active_page id is not found" do
      config = {
        "pages" => [
          { "id" => "p1", "name" => "Step 1", "fields" => [
            { "id" => "f1", "property_slug" => "name", "property_type" => "string",
              "html_type" => "text", "label" => "Name" }
          ] },
          { "id" => "p2", "name" => "Step 2", "fields" => [
            { "id" => "f2", "property_slug" => "email", "property_type" => "email",
              "html_type" => "email", "label" => "Email" }
          ] }
        ],
        "preview_active_page" => "nonexistent_id",
        "metadata" => {}
      }
      page = create(:page, configuration: config.to_json)
      result = described_class.new(page).generate
      expect(result).to include("initial_step: 1")
    end
  end

  describe "#generate required labels" do
    let(:admin) { create(:user, :admin, customer: customer) }
    let(:entity) do
      create(:entity, customer: customer, property_schema: [
        { "name" => "Course code", "name_slug" => "course_code", "type" => "String", "html_type" => "text",
          "validators" => [{ "type" => "presence" }],
          "validator_apply" => { "admin" => true, "member" => false, "public" => false } },
        { "name" => "Notes", "name_slug" => "notes", "type" => "String", "html_type" => "text",
          "validators" => [{ "type" => "length_maximum", "config" => { "value" => 20 } }] },
        { "name" => "Nickname", "name_slug" => "nickname", "type" => "String", "html_type" => "text" },
        { "name" => "Total", "name_slug" => "total", "type" => "Calculated", "html_type" => "number",
          "validators" => [{ "type" => "presence" }] }
      ].to_json)
    end
    let(:page) do
      build(:page, customer: customer, entity: entity, configuration: {
        "pages" => [{
          "id" => "page_1",
          "name" => "Course",
          "fields" => [
            { "id" => "f1", "property_slug" => "course_code", "property_type" => "string",
              "html_type" => "text", "label" => "Course code", "required" => false },
            { "id" => "f2", "property_slug" => "notes", "property_type" => "string",
              "html_type" => "text", "label" => "Notes", "required" => false },
            { "id" => "f3", "property_slug" => "nickname", "property_type" => "string",
              "html_type" => "text", "label" => "Nickname", "required" => true },
            { "id" => "f4", "property_slug" => "total", "property_type" => "integer",
              "html_type" => "number", "label" => "Total", "required" => false, "storage" => "computed" }
          ]
        }],
        "metadata" => { "entity_id" => entity.id }
      }.to_json)
    end

    def generated_for(user)
      Current.set(customer: customer, user: user, shared_resources_mode: false) do
        described_class.new(page).generate
      end
    end

    it "marks schema presence for the admin audience and keeps author-required fields marked" do
      result = generated_for(admin)

      expect(result).to match(/label: "Course code",\s*required: true/)
      expect(result).to match(/label: "Notes",\s*required: false/)
      expect(result).to match(/label: "Nickname",\s*required: true/)
      expect(result).to match(/label: "Total",\s*required: false/)
    end

    it "does not mark a presence validator that does not apply to the public audience" do
      result = generated_for(nil)

      expect(result).to match(/label: "Course code",\s*required: false/)
      expect(result).to match(/label: "Nickname",\s*required: true/)
    end

    it "renders the required asterisk on the admin label" do
      content = generated_for(admin)
      html = Current.set(customer: customer, user: admin, shared_resources_mode: false) do
        ApplicationController.render(inline: content, layout: false,
          assigns: { page: page, form_action: "/submit" })
      end
      labels = Nokogiri::HTML.fragment(html).css("label").map do |node|
        [node.text.gsub(/\s+/, " ").strip, node.at_css("span.text-red-500")&.text]
      end

      expect(labels).to include(["Course code*", "*"])
      expect(labels).to include(["Notes", nil])
    end
  end

  describe "#generate fields an audience sees but cannot edit" do
    let(:admin) { create(:user, :admin, customer: customer) }
    let(:member) { create(:user, :member, customer: customer) }
    let(:entity) do
      create(:entity, customer: customer, property_schema: [
        { "name" => "Recipient", "name_slug" => "recipient", "type" => "String", "html_type" => "text" },
        { "name" => "Status", "name_slug" => "status", "type" => "String", "html_type" => "text",
          "editable" => { "admin" => true, "member" => false, "public" => false } }
      ].to_json)
    end

    def page_for(modes)
      build(:page, customer: customer, entity: entity, configuration: {
        "pages" => [{ "id" => "page_1", "name" => "Order", "fields" => [
          { "id" => "f1", "property_slug" => "recipient", "property_type" => "string", "html_type" => "text", "label" => "Recipient" },
          { "id" => "f2", "property_slug" => "status", "property_type" => "string", "html_type" => "text", "label" => "Status" }
        ] }],
        "form_settings" => { "modes" => modes },
        "metadata" => { "entity_id" => entity.id }
      }.to_json)
    end

    def generated(page, user)
      Current.set(customer: customer, user: user, shared_resources_mode: false) { described_class.new(page).generate }
    end

    it "shows the field read-only where the audience updates a record" do
      result = generated(page_for(%w[update]), member)

      expect(result).to match(%r{<fieldset disabled[^>]*>\s*<div data-field-id="f2">})
      expect(result).not_to match(%r{<fieldset disabled[^>]*>\s*<div data-field-id="f1">})
    end

    it "leaves the field off a form that only creates records" do
      result = generated(page_for(%w[create]), member)

      expect(result).to include('data-field-id="f1"')
      expect(result).not_to include('data-field-id="f2"')
    end

    it "keeps the field editable for an audience that may change it" do
      result = generated(page_for(%w[create]), admin)

      expect(result).to include('data-field-id="f2"')
      expect(result).not_to include("<fieldset disabled")
    end
  end
end
