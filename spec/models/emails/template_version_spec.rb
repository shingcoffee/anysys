# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::TemplateVersion, type: :model do
  let_it_be(:customer) { create(:customer) }

  def create_template(**overrides)
    create(:email_template, customer: customer, **overrides)
  end

  describe "validations" do
    it "is valid when auto-committed by the parent template" do
      template = create_template
      expect(template.template_versions.first).to be_valid
    end
  end

  describe "associations" do
    it "belongs to its parent template" do
      template = create_template
      version = template.template_versions.first
      expect(version.email_template).to eq(template)
    end

    it "belongs to a content row holding the definition payload" do
      template = create_template(subject: "Hi there")
      version = template.template_versions.first
      expect(version.content).to be_a(Emails::TemplateContent)
      expect(version.payload_json["subject"]).to eq("Hi there")
    end
  end

  describe "#payload_json" do
    it "parses the JSON snapshot payload" do
      template = create_template(subject: "Hi", body_html: "<p>Body</p>", editor_type: "code")
      version = template.template_versions.first

      expect(version.payload_json).to include(
        "subject" => "Hi",
        "body_html" => "<p>Body</p>",
        "editor_type" => "code"
      )
    end
  end

  describe "lineage" do
    it "records based_on_version_id when a new version is committed" do
      template = create_template(subject: "A")
      first_version = template.current_version

      template.update!(subject: "B")
      second_version = template.current_version.reload

      expect(second_version.based_on_version_id).to eq(first_version.id)
      expect(second_version.based_on_version_number).to eq(first_version.version_number)
    end
  end
end
