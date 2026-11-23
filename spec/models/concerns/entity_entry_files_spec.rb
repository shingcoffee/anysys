# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityEntryFiles do
  let_it_be(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Title", "name_slug" => "title", "type" => "Types::String", "html_type" => "text" },
      { "name" => "Contract", "name_slug" => "contract", "type" => "Types::String", "html_type" => "file",
        "config" => { "accept" => ".pdf,image/*" } },
      { "name" => "Photo", "name_slug" => "photo", "type" => "Types::String", "html_type" => "image" },
      { "name" => "Scans", "name_slug" => "scans", "type" => "Types::String", "html_type" => "file",
        "config" => { "multiple" => true } },
      { "name" => "Sheet", "name_slug" => "sheet", "type" => "Types::String", "html_type" => "file",
        "config" => { "accept" => ".csv,.msg" } }
    ].to_json)
  end
  let(:model) { EntityEntry.build_for(entity) }
  let(:png) { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/test.png"), "image/png") }

  def entry(**attrs) = model.new(customer_id: customer.id, **attrs)
  def pdf(name = "terms.pdf") = { io: StringIO.new("%PDF-1.4\n%%EOF\n"), filename: name }

  it "declares an attachment per file field, several for a multiple one" do
    expect(model.reflect_on_attachment(:contract).macro).to eq(:has_one_attached)
    expect(model.reflect_on_attachment(:photo).macro).to eq(:has_one_attached)
    expect(model.reflect_on_attachment(:scans).macro).to eq(:has_many_attached)
    expect(model.reflect_on_attachment(:title)).to be_nil
    expect(EntityEntry.file_attributes).to be_empty
  end

  it "attaches an upload on save, stamps its blob with the record's customer and leaves data alone" do
    record = entry(title: "A", photo: png)
    record.save!

    record = model.find(record.id)
    expect(record.photo).to be_attached
    expect(record.photo.blob.customer_id).to eq(customer.id)
    expect(record.photo.content_type).to eq("image/png")
    expect(record.data_json).to eq("title" => "A")
  end

  it "keeps the stored file for a blank value or the attachment itself" do
    record = entry(photo: png).tap(&:save!)
    blob_id = record.photo.blob.id

    record = model.find(record.id)
    ["", nil, [""], record.photo].each do |value|
      record.photo = value
      record.save!
    end
    expect(model.find(record.id).photo.blob.id).to eq(blob_id)
  end

  it "attaches every file of a multiple field and ignores blanks among them" do
    record = entry(scans: ["", pdf("a.pdf"), pdf("b.pdf")]).tap(&:save!)

    expect(model.find(record.id).scans.map { |scan| scan.filename.to_s }).to contain_exactly("a.pdf", "b.pdf")
    expect(model.find(record.id).tap { |r| r.scans = [""] }.tap(&:save!).scans.count).to eq(2)
  end

  it "takes the last file when a single field is given several" do
    record = entry(contract: [pdf("a.pdf"), pdf("b.pdf")]).tap(&:save!)

    expect(model.find(record.id).contract.filename.to_s).to eq("b.pdf")
  end

  describe "validation" do
    it "refuses a file that is not an image for an image field, whatever its name" do
      record = entry(photo: pdf("photo.png"))

      expect(record).not_to be_valid
      expect(record.errors[:photo]).to eq([I18n.t("maint_core.errors.validations.file_not_image")])
    end

    it "refuses a type outside the accepted list and accepts one in it" do
      refused = entry(contract: { io: StringIO.new("plain words"), filename: "notes.txt" })
      expect(refused).not_to be_valid
      expect(refused.errors[:contract])
        .to eq([I18n.t("maint_core.errors.validations.file_type_not_accepted", types: ".pdf, image/*")])

      expect(entry(contract: pdf)).to be_valid
      expect(entry(contract: png)).to be_valid
    end

    it "refuses a program or picture named with an accepted extension" do
      program = { io: StringIO.new("MZ#{"\0" * 64}"), filename: "invoice.pdf", content_type: "application/pdf" }
      refused = entry(contract: program)

      expect(refused).not_to be_valid
      expect(refused.errors[:contract])
        .to eq([I18n.t("maint_core.errors.validations.file_type_not_accepted", types: ".pdf, image/*")])
      expect(entry(sheet: { io: File.open(png.path), filename: "rows.csv" })).not_to be_valid
    end

    it "identifies a new file from its bytes and name, not the type its sender declared" do
      csv = Rack::Test::UploadedFile.new(StringIO.new("id,total\n1,9\n"), "application/vnd.ms-excel",
                                         original_filename: "rows.csv")
      record = entry(sheet: csv)

      expect(record).to be_valid
      expect(record.sheet.content_type).to eq("text/csv")
    end

    it "takes an extension Marcel only sees as an Office container by its name" do
      ole = "\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1".b + ("\0".b * 600)

      expect(entry(sheet: { io: StringIO.new(ole), filename: "mail.msg" })).to be_valid
    end

    it "refuses a stored blob of another tenant, by signed id or as the blob" do
      foreign = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4\n"), filename: "x.pdf")
      foreign.update_column(:customer_id, create(:customer).id)
      unstamped = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4\n"), filename: "y.pdf")
      own = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4\n"), filename: "z.pdf")
      own.update_column(:customer_id, customer.id)

      [foreign.signed_id, foreign, unstamped.signed_id].each do |value|
        record = entry(contract: value)
        expect(record).not_to be_valid
        expect(record.errors[:contract]).to eq([I18n.t("maint_core.errors.validations.file_not_found")])
      end
      expect(entry(scans: [own.signed_id, foreign])).not_to be_valid
      expect(entry(contract: own.signed_id).tap(&:save!).contract.blob).to eq(own)
    end

    it "refuses a file over the size limit" do
      stub_const("EntityEntryFiles::MAX_BYTES", 4)

      record = entry(scans: [pdf])
      expect(record).not_to be_valid
      expect(record.errors[:scans]).to eq([I18n.t("maint_core.errors.validations.file_too_large", max: "4 Bytes")])
    end

    it "has a required File field's contract refuse it empty and take an upload or a stored file" do
      required = create(:entity, customer: customer, property_schema: [
        { "name" => "Photo", "name_slug" => "photo", "type" => "Types::String", "html_type" => "image",
          "validators" => [{ "type" => "presence" }] }
      ].to_json)
      model = EntityEntry.build_for(required)
      contract = EntityEntryContract.build_for(required)

      empty = contract.new(model.new(customer_id: customer.id))
      expect(empty.validate({})).to be(false)
      expect(empty.errors[:photo]).to be_present
      expect(contract.new(model.new(customer_id: customer.id)).validate("photo" => png)).to be(true)

      stored = model.create!(customer_id: customer.id, photo: png)
      expect(contract.new(model.find(stored.id)).validate({})).to be(true)
    end

    it "does not re-check files a record already holds" do
      record = entry(contract: pdf).tap(&:save!)
      entity.update!(property_schema: entity.property_schema_json.map do |attribute|
        attribute["name_slug"] == "contract" ? attribute.merge("config" => { "accept" => ".docx" }) : attribute
      end.to_json)

      reloaded = EntityEntry.build_for(entity.reload).find(record.id)
      reloaded.title = "Changed"
      expect(reloaded).to be_valid
    end
  end

  describe "reading" do
    it "gives flowchart paths the attachment and templates the filenames" do
      record = entry(contract: pdf, scans: [pdf("a.pdf")]).tap(&:save!)
      record = model.find(record.id)

      expect(record.flowchart_value("contract")).to be_a(ActiveStorage::Attached::One)
      expect(record.flowchart_value("photo")).to be_nil
      expect(record.to_liquid).to include("contract" => "terms.pdf", "photo" => nil, "scans" => ["a.pdf"])
    end
  end

  describe "destroying" do
    it "purges the files of a record destroyed through its entity class" do
      record = entry(photo: png).tap(&:save!)

      expect { model.find(record.id).destroy! }.to have_enqueued_job(ActiveStorage::PurgeJob).exactly(:once)
      expect(ActiveStorage::Attachment.where(record_type: "EntityEntry", record_id: record.id)).to be_empty
    end

    it "purges the files of a record destroyed through EntityEntry itself" do
      record = entry(photo: png).tap(&:save!)

      expect { EntityEntry.find(record.id).destroy! }.to have_enqueued_job(ActiveStorage::PurgeJob).exactly(:once)
      expect(ActiveStorage::Attachment.where(record_type: "EntityEntry", record_id: record.id)).to be_empty
    end
  end
end
