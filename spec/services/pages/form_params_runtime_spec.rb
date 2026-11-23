# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::FormParams do
  let_it_be(:customer) { create(:customer) }
  let(:entity) { create(:entity, customer: customer, property_schema: schema.to_json) }
  let(:schema) { [{ "name_slug" => "name" }, { "name_slug" => "email" }] }
  let(:config) { {} }
  let(:page) { double(customer_id: customer.id, configuration_json: config) }

  def permit(values)
    described_class.permit(page: page, entity: entity, audience: "public", params: ActionController::Parameters.new(values))
  end

  it "does not fall back to forged flat values when entity has the wrong shape" do
    expect(permit(entity: ["bad"], name: "forged")).to eq({})
  end

  it "returns no bridge sections from permit_parts for a page without bridge fields" do
    parts = described_class.permit_parts(page: page, entity: entity, audience: "public",
                                         params: ActionController::Parameters.new(entity: { name: "Ann" }))
    expect(parts).to eq([{ "name" => "Ann" }, {}])
  end

  it "rejects nested objects and arrays for scalar fields" do
    expect(permit(entity: { name: { value: "forged" }, email: ["a@example.com"] })).to eq({})
  end

  context "multi-select" do
    let(:schema) { [{ "name_slug" => "choices", "html_type" => "multi-select" }] }

    it "accepts only arrays of scalars" do
      expect(permit(entity: { choices: %w[a b] })).to eq("choices" => %w[a b])
      expect(permit(entity: { choices: [{ admin: "1" }] })).to eq({})
      expect(permit(entity: { choices: "a" })).to eq({})
    end
  end

  context "file upload" do
    let(:schema) { [{ "name_slug" => "attachment", "html_type" => "file" }] }

    it "preserves the upload and its bytes" do
      file = Tempfile.new("runtime-upload")
      file.write("uploaded bytes")
      file.rewind
      upload = ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: "upload.txt", type: "text/plain")
      result = permit(entity: { attachment: upload })
      expect(result["attachment"]).to equal(upload)
      expect(result["attachment"].read).to eq("uploaded bytes")
    ensure
      file&.close!
    end
  end

  context "schema-derived fields" do
    let(:schema) { [] }

    it "drops client values and page calculations for read-only schema attributes" do
      allow(entity).to receive(:property_schema_json).and_return([
        { "name_slug" => "total", "type" => "Calculated" }, { "name_slug" => "count", "type" => "Computed" }
      ])
      expect(permit(total: "999", count: "999")).to eq({})
    end
  end

  context "namespaces" do
    let(:schema) do
      [{ "name_slug" => "email" }, { "name_slug" => "role", "visibility" => { "public" => false } }]
    end
    let(:bridge) do
      create(:entity, customer: customer, name: "enrollment", property_schema: [
        { "name_slug" => "score" }, { "name_slug" => "internal", "visibility" => { "public" => false } }
      ].to_json)
    end
    let(:config) do
      { "pages" => [{ "fields" => [
        { "id" => "email", "property_slug" => "email", "source" => "base_model", "source_section" => "User" },
        { "id" => "role", "property_slug" => "role", "source" => "base_model", "source_section" => "User" },
        { "id" => "score", "property_slug" => "score", "source" => "bridge", "source_section" => bridge.name },
        { "id" => "internal", "property_slug" => "internal", "source" => "bridge", "source_section" => bridge.name }
      ] }] }
    end

    before do
      allow(entity).to receive(:extended_model).and_return("User")
      allow(entity).to receive(:associations_json).and_return([{ "bridge_entity_id" => bridge.id }])
    end

    it "excludes unsupported base fields and filters associations by declaration, schema and audience" do
      expect(permit(
        base: { user: { email: "safe@example.com", role: "owner", evil: "1" }, other: { email: "forged" } },
        assoc: { enrollment: { score: "90", internal: "secret", evil: "1" }, other: { score: "1" } }
      )).to eq("entity" => {}, "assoc" => { "enrollment" => { "score" => "90" } })
    end

    it "returns the primary attributes and bridge sections separately from permit_parts" do
      parts = described_class.permit_parts(
        page: page, entity: entity, audience: "public",
        params: ActionController::Parameters.new(entity: { email: "a@example.com" }, assoc: { enrollment: { score: "90" } })
      )
      expect(parts).to eq([{}, { "enrollment" => { "score" => "90" } }])
    end

    it "rejects nested scalar values within allowed namespaces" do
      result = permit(base: { user: { email: ["forged"] } }, assoc: { enrollment: { score: { value: "1" } } })
      expect(result).to eq("entity" => {}, "assoc" => { "enrollment" => {} })
    end

    it "rejects a foreign-tenant bridge even if its id is in association metadata" do
      bridge.update_column(:customer_id, create(:customer).id)
      expect(permit(assoc: { enrollment: { score: "99" } })).to eq({})
    end

    it "does not expose a base input merely because its slug also exists in the entity schema" do
      boundary = described_class.new(page: page, entity: entity, params: {}, audience: "admin")
      expect(boundary.visible_field?(config["pages"].first["fields"].first)).to be(false)
    end

    it "recognizes malformed base namespaces as unsupported submissions" do
      ["User", [], false, { "user" => { "email" => "forged" } }].each do |base|
        expect(described_class.base_submission?(ActionController::Parameters.new(base: base))).to be(true)
      end
      expect(described_class.base_submission?({ base: {} })).to be(false)
      expect(described_class.base_submission?({})).to be(false)
    end
  end

  context "calculation audience" do
    let(:schema) do
      [{ "name_slug" => "quantity" }, { "name_slug" => "total" },
       { "name_slug" => "internal", "visibility" => { "public" => false } }]
    end
    let(:config) do
      { "calculations" => [
        { "target_field_id" => "total", "formula" => "{quantity} * 2" },
        { "target_field_id" => "internal", "formula" => "123" },
        { "target_field_id" => "unknown", "formula" => "123" }
      ] }
    end

    it "recomputes a writable target but cannot reintroduce audience-hidden or unknown keys" do
      expect(permit(quantity: "3", total: "999", internal: "999")).to eq("quantity" => "3", "total" => 6.0)
    end

    it "does not use an audience-hidden calculated intermediate to produce a visible result" do
      config["calculations"].first["formula"] = "{internal} * 2"
      expect(permit(quantity: "3", total: "999", internal: "999")).to eq("quantity" => "3")
    end
  end
end
