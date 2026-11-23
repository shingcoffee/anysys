# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::Attachments do
  it "accepts a small png" do
    errors = ActiveModel::Errors.new(AiAssistant::Message.new)
    described_class.validate([ png_upload ], errors: errors)
    expect(errors).to be_empty
  end

  it "rejects a disallowed type" do
    errors = ActiveModel::Errors.new(AiAssistant::Message.new)
    described_class.validate(
      [ txt_upload ],
      errors: errors
    )
    expect(errors[:images]).to include(I18n.t("ai_assistant.errors.invalid_image_type"))
  end

  it "accepts eight images in one message" do
    errors = ActiveModel::Errors.new(AiAssistant::Message.new)
    described_class.validate(Array.new(8) { png_upload }, errors: errors)
    expect(described_class::MAX_FILES).to eq(8)
    expect(errors).to be_empty
  end

  it "rejects too many files" do
    errors = ActiveModel::Errors.new(AiAssistant::Message.new)
    files = Array.new(described_class::MAX_FILES + 1) { png_upload }
    described_class.validate(files, errors: errors)
    expect(errors[:images]).to include(I18n.t("ai_assistant.errors.too_many_images", count: described_class::MAX_FILES))
  end

  it "rejects a file that is too large" do
    errors = ActiveModel::Errors.new(AiAssistant::Message.new)
    oversized = Struct.new(:content_type, :size).new("image/png", described_class::MAX_BYTES + 1)
    described_class.validate([ oversized ], errors: errors)
    expect(errors[:images]).to include(I18n.t("ai_assistant.errors.image_too_large"))
  end

  it "rejects files that are each allowed but together over the total cap" do
    errors = ActiveModel::Errors.new(AiAssistant::Message.new)
    count = (described_class::MAX_TOTAL_BYTES / described_class::MAX_BYTES) + 1
    files = Array.new(count) { Struct.new(:content_type, :size).new("image/png", described_class::MAX_BYTES) }
    described_class.validate(files, errors: errors)
    expect(errors[:images]).to eq([ I18n.t("ai_assistant.errors.images_too_large_total") ])
  end

  it "treats a missing size as too large" do
    errors = ActiveModel::Errors.new(AiAssistant::Message.new)
    upload = Object.new
    def upload.content_type
      "image/png"
    end
    described_class.validate([ upload ], errors: errors)
    expect(errors[:images]).to include(I18n.t("ai_assistant.errors.image_too_large"))
  end

  it "reads byte_size when size is not present" do
    errors = ActiveModel::Errors.new(AiAssistant::Message.new)
    described_class.validate([ Struct.new(:content_type, :byte_size).new("image/png", 12) ], errors: errors)
    expect(errors).to be_empty
  end

  it "rejects images when the generation vendor does not support them" do
    create(:ai_assistant_provider_settings,
           provider: "deepseek",
           api_key: "sk-deep",
           transcribe_active: false,
           generation_active: true)
    errors = ActiveModel::Errors.new(AiAssistant::Message.new)
    described_class.validate([ png_upload ], errors: errors)
    expect(errors[:images]).to include(I18n.t("ai_assistant.errors.images_unsupported"))
  end
end
