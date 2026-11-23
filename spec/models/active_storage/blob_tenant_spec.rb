# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ActiveStorage::Blob tenant stamping", type: :model do
  let(:customer)   { create(:customer) }
  let(:other_id)   { customer.id + 9999 }

  around do |example|
    # Use Current.set to set and automatically reset the tenant context
    Current.set(customer: customer) { example.run }
  end

  def create_blob
    ActiveStorage::Blob.create_and_upload!(
      io:           StringIO.new("x"),
      filename:     "a.txt",
      content_type: "text/plain"
    )
  end

  it "stamps the blob with the current customer_id on create" do
    blob = create_blob
    expect(blob.customer_id).to eq(customer.id)
  end

  it "for_customer scope includes the blob for the correct customer" do
    blob = create_blob
    expect(ActiveStorage::Blob.for_customer(customer.id)).to include(blob)
  end

  it "for_customer scope excludes the blob for a different customer" do
    blob = create_blob
    expect(ActiveStorage::Blob.for_customer(other_id)).not_to include(blob)
  end

  it "does not overwrite an already-set customer_id" do
    explicit_cid = customer.id + 1
    blob = ActiveStorage::Blob.create_and_upload!(
      io:           StringIO.new("y"),
      filename:     "b.txt",
      content_type: "text/plain",
      record:       nil
    )
    # Manually verify the before_create guard (||=) doesn't clobber an explicit value
    # by building + saving directly
    partial = ActiveStorage::Blob.new(
      key:          ActiveStorage::Blob.generate_unique_secure_token,
      filename:     "c.txt",
      content_type: "text/plain",
      byte_size:    1,
      checksum:     "abc",
      service_name: ActiveStorage::Blob.service.name.to_s
    )
    partial.customer_id = explicit_cid
    partial.save!
    expect(partial.customer_id).to eq(explicit_cid)
  end
end
