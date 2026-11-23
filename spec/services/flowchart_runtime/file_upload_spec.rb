# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::FileUpload do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Title", "name_slug" => "title", "type" => "Types::String", "html_type" => "text" },
      { "name" => "Contract", "name_slug" => "contract", "type" => "Types::String", "html_type" => "file" },
      { "name" => "Photo", "name_slug" => "photo", "type" => "Types::String", "html_type" => "image" },
      { "name" => "Scans", "name_slug" => "scans", "type" => "Types::String", "html_type" => "file",
        "config" => { "multiple" => true } }
    ].to_json)
  end
  let(:ctx) { { customer_id: customer.id, bound_entity: entity, audience: "admin" } }
  let(:record) { EntityEntry.build_for(entity).create!(customer_id: customer.id, title: "A") }
  let(:payload) { { "filename" => "terms.pdf", "content" => "%PDF-1.4\n%%EOF\n", "content_type" => "application/pdf" } }

  def stored(slug) = EntityEntry.build_for(entity).find(record.id).public_send(slug)

  it "stores a file payload in a single-file field and saves the record" do
    result = described_class.attach(ctx, record, "contract", payload)

    contract = stored(:contract)
    expect(contract.filename.to_s).to eq("terms.pdf")
    expect(contract.content_type).to eq("application/pdf")
    expect(contract.blob.customer_id).to eq(customer.id)
    expect(result).to include("blob_id" => contract.blob.id, "filename" => "terms.pdf",
                              "content_type" => "application/pdf", "byte_size" => payload["content"].bytesize)
    expect(ActiveStorage::Blob.find_signed(result["signed_id"])).to eq(contract.blob)
  end

  it "replaces a single-file field's file and adds to a multiple-file field" do
    described_class.attach(ctx, record, "contract", payload)
    described_class.attach(ctx, record, "contract", payload.merge("filename" => "v2.pdf"))
    described_class.attach(ctx, record, "scans", payload.merge("filename" => "a.pdf"))
    described_class.attach(ctx, record, "scans", payload.merge("filename" => "b.pdf"))

    expect(stored(:contract).filename.to_s).to eq("v2.pdf")
    expect(stored(:scans).map { |scan| scan.filename.to_s }).to contain_exactly("a.pdf", "b.pdf")
  end

  it "names raw bytes upload.bin unless a filename is given" do
    expect(described_class.attach(ctx, record, "scans", "id,total\n1,9\n")["filename"]).to eq("upload.bin")
    expect(described_class.attach(ctx, record, "contract", payload, filename: "signed.pdf")["filename"]).to eq("signed.pdf")
  end

  it "attaches a stored blob of the run's tenant, such as a generate_document result" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4\n"), filename: "quote.pdf")
    blob.update_column(:customer_id, customer.id)

    described_class.attach(ctx, record, "contract", { "blob_id" => blob.id, "filename" => "quote.pdf" })

    expect(stored(:contract).blob).to eq(blob)
  end

  it "copies another record's file field onto this one" do
    other = EntityEntry.build_for(entity).create!(customer_id: customer.id)
    described_class.attach(ctx, other, "contract", payload)

    described_class.attach(ctx, record, "scans", EntityEntry.build_for(entity).find(other.id).contract)

    expect(stored(:scans).map { |scan| scan.filename.to_s }).to eq(["terms.pdf"])
  end

  it "refuses another tenant's blob and record" do
    foreign = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("x"), filename: "x.pdf")
    foreign.update_column(:customer_id, create(:customer).id)

    expect { described_class.attach(ctx, record, "contract", { "blob_id" => foreign.id }) }
      .to raise_error(described_class::Error, /not found/)
    expect { described_class.attach(ctx, record, "contract", { "signed_id" => foreign.signed_id }) }
      .to raise_error(described_class::Error, /not found/)
    expect { described_class.attach(ctx.merge(customer_id: customer.id + 1), record, "contract", payload) }
      .to raise_error(described_class::Error, /tenant/)
  end

  it "refuses a field that is not a File or Image field, and a missing file" do
    expect { described_class.attach(ctx, record, "title", payload) }.to raise_error(described_class::Error, /not a file field/)
    expect { described_class.attach(ctx, record, "contract", nil) }.to raise_error(described_class::Error, /no file/)
    expect { described_class.attach(ctx, nil, "contract", payload) }.to raise_error(described_class::Error, /record is required/)
  end

  it "returns false with the record's reasons when it refuses the file" do
    expect(described_class.attach(ctx, record, "photo", payload)).to be(false)

    expect(ctx[:error_details]).to include(a_hash_including("field" => "photo",
                                                            "message" => I18n.t("maint_core.errors.validations.file_not_image")))
    expect(stored(:photo)).not_to be_attached
  end

  it "only stages the file when save is off" do
    result = described_class.attach(ctx, record, "contract", payload, save: false)

    expect(result).to include("blob_id" => nil, "signed_id" => nil, "filename" => "terms.pdf")
    expect(stored(:contract)).not_to be_attached
    record.save!
    expect(stored(:contract)).to be_attached
  end
end
