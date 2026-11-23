# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#format_datetime" do
    it "formats datetime with the locale long time format" do
      datetime = Time.zone.local(2024, 1, 15, 14, 30, 45)
      expect(helper.format_datetime(datetime)).to eq(I18n.l(datetime, format: :long))
    end

    it "localizes datetime in zh-CN" do
      datetime = Time.zone.local(2024, 1, 15, 14, 30, 45)
      I18n.with_locale(:"zh-CN") do
        expect(helper.format_datetime(datetime)).to eq(I18n.l(datetime, format: :long))
      end
    end

    it "returns dash for nil datetime" do
      expect(helper.format_datetime(nil)).to eq("-")
    end

    it "returns dash for blank datetime" do
      expect(helper.format_datetime("")).to eq("-")
    end
  end

  describe "#format_date" do
    it "formats date with the locale long date format" do
      datetime = Time.zone.local(2024, 1, 15, 14, 30, 45)
      expect(helper.format_date(datetime)).to eq(I18n.l(datetime.to_date, format: :long))
    end

    it "returns dash for nil date" do
      expect(helper.format_date(nil)).to eq("-")
    end

    it "returns dash for blank date" do
      expect(helper.format_date("")).to eq("-")
    end
  end

  describe "#validator_label" do
    it "returns 'Required' for presence validator" do
      expect(helper.validator_label("presence")).to eq("Required")
    end

    it "returns '>=' for greater_than_or_equal_to validator" do
      expect(helper.validator_label("greater_than_or_equal_to")).to eq(">=")
    end

    it "returns '<=' for less_than_or_equal_to validator" do
      expect(helper.validator_label("less_than_or_equal_to")).to eq("<=")
    end

    it "returns '==' for equal_to validator" do
      expect(helper.validator_label("equal_to")).to eq("==")
    end

    it "returns '!=' for not_equal_to validator" do
      expect(helper.validator_label("not_equal_to")).to eq("!=")
    end

    it "returns '>' for greater_than validator" do
      expect(helper.validator_label("greater_than")).to eq(">")
    end

    it "returns '<' for less_than validator" do
      expect(helper.validator_label("less_than")).to eq("<")
    end

    it "returns 'Email' for format_email validator" do
      expect(helper.validator_label("format_email")).to eq("Email")
    end

    it "returns 'URL' for format_url validator" do
      expect(helper.validator_label("format_url")).to eq("URL")
    end

    it "returns 'MinLen' for length_minimum validator" do
      expect(helper.validator_label("length_minimum")).to eq("MinLen")
    end

    it "returns 'MaxLen' for length_maximum validator" do
      expect(helper.validator_label("length_maximum")).to eq("MaxLen")
    end

    it "returns original value for unknown validator" do
      expect(helper.validator_label("custom_validator")).to eq("custom_validator")
    end

    it "handles symbol input" do
      expect(helper.validator_label(:presence)).to eq("Required")
    end
  end

  describe "#render_validator_badges" do
    it "returns dash for empty validators" do
      result = helper.render_validator_badges([])
      expect(result).to include("-")
      expect(result).to include("text-text-muted")
    end

    it "returns dash for nil validators" do
      result = helper.render_validator_badges(nil)
      expect(result).to include("-")
    end

    it "renders badges for validators" do
      result = helper.render_validator_badges(["presence", "format_email"])

      expect(result).to include("Required")
      expect(result).to include("Email")
      expect(result).to include("badge-default")
    end

    it "handles single validator as non-array" do
      result = helper.render_validator_badges("presence")
      expect(result).to include("Required")
    end

    it "includes title attribute with original validator name" do
      result = helper.render_validator_badges(["presence"])
      expect(result).to include("title=")
    end
  end

  describe "#organize_entity_fields" do
    it "delegates to EntityFieldOrganizer and returns a result" do
      customer = create(:customer)
      entity   = create(:entity, customer: customer)
      result   = helper.organize_entity_fields(entity)
      expect(result).not_to be_nil
    end
  end

  describe "#link_to_entity" do
    let_it_be(:customer) { create(:customer) }

    it "renders a link when given an Entity object directly" do
      entity = create(:entity, customer: customer, name: "Orders")
      result = helper.link_to_entity(entity, customer.id)
      expect(result).to include("Orders")
      expect(result).to include("link")
    end

    it "renders a link when given a string ID that matches an entity" do
      entity = create(:entity, customer: customer, name: "Products")
      result = helper.link_to_entity(entity.id.to_s, customer.id)
      expect(result).to include("Products")
      expect(result).to include("link")
    end

    it "renders a link when given a string name that matches an entity" do
      entity = create(:entity, customer: customer, name: "Contacts")
      result = helper.link_to_entity("Contacts", customer.id)
      expect(result).to include("Contacts")
      expect(result).to include("link")
    end

    it "renders a muted span with the fallback text when entity is not found" do
      result = helper.link_to_entity("nonexistent_entity", customer.id)
      expect(result).to include("text-text-muted")
      expect(result).to include("nonexistent_entity")
      expect(result).not_to include("link")
    end

    it "uses custom link_text when provided and entity is found" do
      entity = create(:entity, customer: customer, name: "Invoices")
      result = helper.link_to_entity(entity, customer.id, link_text: "Custom Label")
      expect(result).to include("Custom Label")
      expect(result).not_to include("Invoices")
    end

    it "uses custom link_text in the fallback span when entity not found" do
      result = helper.link_to_entity("ghost", customer.id, link_text: "My Label")
      expect(result).to include("My Label")
      expect(result).to include("text-text-muted")
    end
  end

  describe "#html_type_icon_color" do
    it "returns slate colors for text types" do
      %w[text textarea search password hidden rich-text signature].each do |t|
        expect(helper.html_type_icon_color(t)).to eq(%w[text-slate-500 bg-slate-100/80])
      end
    end

    it "returns violet colors for select/choice types" do
      %w[select multi-select radio checkbox switch].each do |t|
        expect(helper.html_type_icon_color(t)).to eq(%w[text-violet-500 bg-violet-100/80])
      end
    end

    it "returns blue colors for numeric types" do
      %w[number currency range rating].each do |t|
        expect(helper.html_type_icon_color(t)).to eq(%w[text-blue-500 bg-blue-100/80])
      end
    end

    it "returns amber colors for date/time types" do
      %w[date time datetime-local month week].each do |t|
        expect(helper.html_type_icon_color(t)).to eq(%w[text-amber-600 bg-amber-100/80])
      end
    end

    it "returns emerald colors for contact types" do
      %w[email tel url].each do |t|
        expect(helper.html_type_icon_color(t)).to eq(%w[text-emerald-500 bg-emerald-100/80])
      end
    end

    it "returns rose colors for file/media types" do
      %w[file image color].each do |t|
        expect(helper.html_type_icon_color(t)).to eq(%w[text-rose-500 bg-rose-100/80])
      end
    end

    it "returns gray fallback for unknown type" do
      expect(helper.html_type_icon_color("unknown_type")).to eq(%w[text-gray-400 bg-gray-100])
    end

    it "returns gray fallback for nil" do
      expect(helper.html_type_icon_color(nil)).to eq(%w[text-gray-400 bg-gray-100])
    end
  end

  describe "#html_type_icon_path" do
    it "returns text lines path for textarea / rich-text" do
      path = helper.html_type_icon_path("textarea")
      expect(path).to eq("M4 6h16M4 10h16M4 14h10")
      expect(helper.html_type_icon_path("rich-text")).to eq(path)
    end

    it "returns chevron path for select / multi-select / radio" do
      path = helper.html_type_icon_path("select")
      expect(path).to eq("M8 9l4-4 4 4m0 6l-4 4-4-4")
      expect(helper.html_type_icon_path("multi-select")).to eq(path)
      expect(helper.html_type_icon_path("radio")).to eq(path)
    end

    it "returns check-circle path for checkbox / switch" do
      path = helper.html_type_icon_path("checkbox")
      expect(path).to include("9 12l2 2 4-4")
      expect(helper.html_type_icon_path("switch")).to eq(path)
    end

    it "returns hash/number path for number / currency / range / rating" do
      path = helper.html_type_icon_path("number")
      expect(path).to eq("M7 20l4-16m2 16l4-16M6 9h14M4 15h14")
      %w[currency range rating].each do |t|
        expect(helper.html_type_icon_path(t)).to eq(path)
      end
    end

    it "returns calendar path for date / month / week" do
      path = helper.html_type_icon_path("date")
      expect(path).to include("M8 7V3m8 4V3")
      expect(helper.html_type_icon_path("month")).to eq(path)
      expect(helper.html_type_icon_path("week")).to eq(path)
    end

    it "returns clock path for time / datetime-local" do
      path = helper.html_type_icon_path("time")
      expect(path).to include("M12 8v4l3 3")
      expect(helper.html_type_icon_path("datetime-local")).to eq(path)
    end

    it "returns envelope path for email" do
      expect(helper.html_type_icon_path("email")).to include("M3 8l7.89 5.26")
    end

    it "returns phone path for tel" do
      expect(helper.html_type_icon_path("tel")).to include("M3 5a2 2 0 012-2h3.28")
    end

    it "returns link path for url" do
      expect(helper.html_type_icon_path("url")).to include("M13.828 10.172a4 4 0 00-5.656")
    end

    it "returns document path for file" do
      expect(helper.html_type_icon_path("file")).to include("M7 21h10a2 2 0 002-2V9.414")
    end

    it "returns image path for image" do
      expect(helper.html_type_icon_path("image")).to include("M2.25 15.75l5.159-5.159")
    end

    it "returns color swatch path for color" do
      expect(helper.html_type_icon_path("color")).to include("M7 21a4 4 0 01-4-4")
    end

    it "returns signature (pencil) path for signature" do
      expect(helper.html_type_icon_path("signature")).to include("M15.232 5.232l3.536 3.536")
    end

    it "returns lock path for password" do
      expect(helper.html_type_icon_path("password")).to include("M12 15v2m-6 4h12")
    end

    it "returns eye-off path for hidden" do
      expect(helper.html_type_icon_path("hidden")).to include("M13.875 18.825A10.05 10.05 0")
    end

    it "returns search path for search" do
      expect(helper.html_type_icon_path("search")).to include("M21 21l-6-6m2-5")
    end

    it "returns four-line fallback path for unknown type" do
      expect(helper.html_type_icon_path("unknown_type")).to eq("M4 6h16M4 10h16M4 14h16M4 18h16")
    end

    it "returns fallback path for nil" do
      expect(helper.html_type_icon_path(nil)).to eq("M4 6h16M4 10h16M4 14h16M4 18h16")
    end
  end
end
