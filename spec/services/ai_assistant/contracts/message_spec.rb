# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe AiAssistant::Contracts::Message do
  def form_for(body, images: nil)
    described_class.new(OpenStruct.new).tap { |form| form.validate(body: body, images: images) }
  end

  it "is valid with a body" do
    expect(form_for("Hello").errors).to be_empty
  end

  it "is valid with images and a blank body" do
    upload = Struct.new(:content_type, :size).new("image/png", 12)
    expect(form_for(" ", images: [ upload ]).errors).to be_empty
  end

  it "adds a localized error when the body is blank" do
    expect(form_for(" ").errors[:body]).to include(I18n.t("ai_assistant.errors.body_blank"))
  end

  it "adds a localized error when the body is too long" do
    expect(form_for("x" * 8_001).errors[:body]).to include(I18n.t("ai_assistant.errors.body_too_long"))
  end
end
