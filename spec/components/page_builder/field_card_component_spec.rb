# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageBuilder::FieldCardComponent, type: :component do
  let(:full_field) do
    {
      "id"            => "field_abc",
      "label"         => "Email Address",
      "placeholder"   => "you@example.com",
      "required"      => true,
      "width"         => "full",
      "property_slug" => "email",
      "property_type" => "email"
    }
  end

  let(:half_field)  { full_field.merge("width" => "half",  "label" => "First Name", "id" => "field_b") }
  let(:third_field) { full_field.merge("width" => "third", "label" => "Age",        "id" => "field_c") }
  let(:no_placeholder_field) { full_field.merge("placeholder" => nil, "required" => false, "id" => "field_d") }

  # -------------------------------------------------------------------
  # Basic rendering
  # -------------------------------------------------------------------
  describe "full-width required field with placeholder" do
    before { render_inline(described_class.new(field: full_field)) }

    it "renders the field label" do
      expect(page).to have_text("Email Address")
    end

    it "renders the required asterisk" do
      expect(page).to have_css("span.text-red-500", text: "*")
    end

    it "renders the property type badge" do
      expect(page).to have_text("email")
    end

    it "does not render the property slug" do
      expect(page).not_to have_css("span.font-mono", text: "email")
    end

    it "renders the placeholder text" do
      expect(page).to have_text("you@example.com")
    end

    it "sets data-field-id on the wrapper" do
      expect(page).to have_css("[data-field-id='field_abc']")
    end

    it "marks the wrapper as draggable" do
      expect(page).to have_css("[draggable='true']")
    end

    it "applies full-width class" do
      expect(page).to have_css(".w-full")
    end
  end

  # -------------------------------------------------------------------
  # Half-width field
  # -------------------------------------------------------------------
  describe "half-width field" do
    before { render_inline(described_class.new(field: half_field)) }

    it "applies w-1/2 and inline-block classes" do
      expect(page).to have_css(".w-1\\/2")
    end
  end

  # -------------------------------------------------------------------
  # Third-width field
  # -------------------------------------------------------------------
  describe "third-width field" do
    before { render_inline(described_class.new(field: third_field)) }

    it "applies w-1/3 and inline-block classes" do
      expect(page).to have_css(".w-1\\/3")
    end
  end

  # -------------------------------------------------------------------
  # Optional (not required) field without placeholder
  # -------------------------------------------------------------------
  describe "optional field without placeholder" do
    before { render_inline(described_class.new(field: no_placeholder_field)) }

    it "does not render the required asterisk" do
      expect(page).not_to have_css("span.text-red-500")
    end

    it "does not render a placeholder line" do
      expect(page).not_to have_css(".text-gray-400.italic")
    end
  end

  # -------------------------------------------------------------------
  # Accessor delegation helpers
  # -------------------------------------------------------------------
  describe "component accessor methods" do
    let(:component) { described_class.new(field: full_field) }

    it "#field_id returns the id" do
      expect(component.field_id).to eq("field_abc")
    end

    it "#label returns the label" do
      expect(component.label).to eq("Email Address")
    end

    it "#placeholder returns the placeholder" do
      expect(component.placeholder).to eq("you@example.com")
    end

    it "#required? returns true when required" do
      expect(component.required?).to be true
    end

    it "#width defaults to full when absent" do
      component = described_class.new(field: full_field.reject { |k| k == "width" })
      expect(component.width).to eq("full")
    end

    it "#property_type returns the type" do
      expect(component.property_type).to eq("email")
    end
  end
end
