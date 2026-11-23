# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::CodeGenerators::ToolbarComponent, type: :component do
  subject(:rendered) do
    render_inline(described_class.new(
      generator_class: generator_class,
      path: slug,
      customer_id: customer_id
    ))
  end

  let(:customer_id) { "81721200" }
  let(:encoded_slug) { ERB::Util.url_encode(slug) }
  let(:slug) { "element_types/process/validation/version_check_generator" }

  let(:generator_class) do
    Class.new do
      def self._metadata
        { category: :validation, version: "1.2.3", description: "checks version" }
      end

      def self.generator_kind = :step_action
      def self.generator_name = "version_check"
    end
  end



  it "renders a back link to the code generators index" do
    expected_href = "/#{customer_id}/admin/maintenance/platform/code_generators"
    expect(rendered.css("a[href='#{expected_href}']")).not_to be_empty
  end

  it "renders the category, generator name, and version" do
    expect(rendered.text).to include("Validation")
    expect(rendered.text).to include("version_check")
    expect(rendered.text).to include("v1.2.3")
  end

  it "renders an Edit link to the generator edit path" do
    expected_href = "/#{customer_id}/admin/maintenance/platform/code_generators/#{encoded_slug}/edit"
    expect(rendered.css("a[href='#{expected_href}']")).not_to be_empty
    expect(rendered.text).to include("Edit")
  end

  it "renders a Delete button with turbo confirm" do
    expect(rendered.text).to include("Delete")
    delete_form = rendered.css("form[action*='code_generators/#{encoded_slug}'][method='post']")
    expect(delete_form).not_to be_empty
    expect(rendered.css("[data-turbo-confirm]")).not_to be_empty
  end

  it "uses the h-12 fixed header layout from the page-edit toolbar" do
    expect(rendered.css("header.bg-white.border-b")).not_to be_empty
    expect(rendered.css(".h-12")).not_to be_empty
  end
end
