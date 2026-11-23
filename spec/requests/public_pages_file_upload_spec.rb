# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Page submission stores uploaded files on the record", type: :request do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Title", "name_slug" => "title", "type" => "String", "html_type" => "text" },
      { "name" => "Photo", "name_slug" => "photo", "type" => "String", "html_type" => "image" }
    ].to_json)
  end
  let(:page) do
    Current.set(customer: customer) do
      create(:page, :public_only, customer: customer, entity: entity, launched: true, configuration: {
        pages: [{ id: "page_1", name: "Form", order: 1, fields: [
          { id: "f1", field_type: "text", property_slug: "title", property_type: "string", label: "Title",
            source: "entity", source_section: entity.display_label },
          { id: "f2", field_type: "image", html_type: "image", property_slug: "photo", label: "Photo",
            source: "entity", source_section: entity.display_label }
        ] }],
        metadata: { entity_id: entity.id }
      }.to_json)
    end
  end

  def submit(photo)
    post "/#{customer.id}/page/#{page.public_uuid}", params: { entity: { title: "Hello", photo: photo } }
  end

  it "attaches the upload to the new record's Image field as a blob of its tenant" do
    submit(Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/test.png"), "image/png"))

    entry = EntityEntry.build_for(entity).find_by!(entity_id: entity.id)
    expect(entry.photo).to be_attached
    expect(entry.photo.blob).to have_attributes(filename: ActiveStorage::Filename.new("test.png"),
                                                content_type: "image/png", customer_id: customer.id)
    expect(entry.data_json).to eq("title" => "Hello")
  end

  it "refuses a file that is not an image and writes nothing" do
    pdf = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4\n"), "image/png", original_filename: "photo.png")

    expect { submit(pdf) }.not_to(change { EntityEntry.where(entity_id: entity.id).count })
    expect(ActiveStorage::Attachment.where(record_type: "EntityEntry")).to be_empty

    follow_redirect! if response.redirect?
    expect(response.body).to include(I18n.t("maint_core.errors.validations.file_not_image"))
  end
end
