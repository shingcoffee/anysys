# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::MediaPolicy do
  let(:customer) { create(:customer) }
  let(:bytes) { File.binread(Rails.root.join("spec/fixtures/files/test.png")) }

  def stored_image(metadata: { website_media: true }, content_type: "image/png")
    Current.set(customer: customer) do
      ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(bytes), filename: "photo.png", content_type: content_type,
        identify: false, metadata: metadata
      )
    end
  end

  it "admits only explicitly classified, same-tenant raster media to public serving" do
    blob = stored_image
    expect(described_class.public_image?(blob, customer_id: customer.id)).to be(true)
    expect(described_class.public_image?(blob, customer_id: create(:customer).id)).to be(false)
    expect(described_class.public_image?(blob, customer_id: nil)).to be(false)
    expect(described_class.public_image?(nil, customer_id: customer.id)).to be(false)
  end

  it "rejects a generic tenant attachment and a non-image even if it has a media marker" do
    expect(described_class.public_image?(stored_image(metadata: {}), customer_id: customer.id)).to be(false)
    expect(described_class.public_image?(stored_image(metadata: { website_media: "true" }), customer_id: customer.id)).to be(false)
    expect(described_class.public_image?(stored_image(content_type: "text/html"), customer_id: customer.id)).to be(false)
  end

  it "identifies bytes while leaving the IO ready for upload" do
    io = StringIO.new(bytes)
    io.read(8)

    expect(described_class.identified_type(io)).to eq("image/png")
    expect(io.read).to eq(bytes)
  end
end
