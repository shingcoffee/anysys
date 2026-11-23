# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::CompileTemplate do
  let_it_be(:customer) { create(:customer) }

  # rich_text templates derive body_html from the Action Text body via the
  # model's before_validation compile step, so the body must be set before the
  # (validated) save — mirroring the real editor flow.
  def rich_text_template(body)
    build(:email_template, customer: customer, editor_type: "rich_text", body_html: nil).tap do |t|
      t.body = body
      t.save!
    end
  end

  describe ".call" do
    context "with a code editor_type template" do
      let(:template) do
        build(:email_template, customer: customer,
              editor_type: "code",
              body_html: "<p>Hello #{platform_token('first_name')}, welcome!</p>")
      end

      it "returns body_html unchanged" do
        result = described_class.call(template)
        expect(result).to eq("<p>Hello #{platform_token('first_name')}, welcome!</p>")
      end
    end

    context "with a rich_text editor_type template and plain text body" do
      let(:template) { rich_text_template("<div><p>Hi #{platform_token('first_name')}</p></div>") }

      it "returns HTML output" do
        result = described_class.call(template)
        expect(result).to be_a(String)
        expect(result).to include("Hi")
      end

      it "preserves {{token}} placeholders" do
        result = described_class.call(template)
        expect(result).to include(platform_token('first_name'))
      end

      it "is a non-empty HTML string" do
        result = described_class.call(template)
        expect(result).to be_present
      end

      it "matches the editor fragment without ActionText layout chrome" do
        result = described_class.call(template)
        expect(result).not_to include("trix-content")
        expect(result).not_to include("BEGIN")
        expect(result).not_to include("END")
      end
    end

    context "with a rich_text template body containing a Lexxy table" do
      let(:table_html) do
        '<figure class="lexxy-content__table-wrapper"><table><tbody>' \
          '<tr><th class="lexxy-content__table-cell--header"><p>H1</p></th><th class="lexxy-content__table-cell--header"><p>H2</p></th></tr>' \
          '<tr><th class="lexxy-content__table-cell--header"><p>A</p></th><td><p>B</p></td></tr>' \
          "</tbody></table></figure>"
      end
      let(:template) { rich_text_template(table_html) }

      it "inlines border-collapse and width on the table" do
        result = described_class.call(template)
        expect(result).to match(/<table[^>]*style="[^"]*border-collapse: collapse;[^"]*width: 100%;/)
      end

      it "inlines border and padding on every cell" do
        result = described_class.call(template)
        expect(result.scan(/<t[dh][^>]*style="[^"]*border: 1px solid #cecece; padding: 8px; text-align: left;/).size).to eq(4)
      end

      it "adds header background and bold weight to header cells" do
        result = described_class.call(template)
        expect(result.scan(/<th[^>]*style="[^"]*background-color: #f2f2f2; font-weight: bold;/).size).to eq(3)
      end

      it "does not restyle plain cells as headers" do
        result = described_class.call(template)
        td = result[/<td[^>]*>.*?<\/td>/m]
        expect(td).not_to include("background-color")
      end
    end

    context "with a rich_text template body containing no attachments" do
      let(:template) { rich_text_template("<p>Simple content {{token}}</p>") }

      it "blob_ids_for returns an empty array" do
        expect(described_class.blob_ids_for(template)).to eq([])
      end
    end

    context "with a rich_text template body containing an attached image blob" do
      let(:blob) do
        Current.set(customer: customer) do
          ActiveStorage::Blob.create_and_upload!(
            io: StringIO.new("fake image data"),
            filename: "hero.png",
            content_type: "image/png"
          )
        end
      end

      let(:template) do
        t = build(:email_template, customer: customer,
                  editor_type: "rich_text", body_html: nil)
        # Attach via ActionText::Content with the blob's attachment sgid
        attachment_html = ActionText::Attachment.from_attachable(blob).to_s
        t.body = "<div>#{attachment_html}</div>"
        t.save!
        t.reload
        t
      end

      it "blob_ids_for returns the attached blob id" do
        ids = described_class.blob_ids_for(template)
        expect(ids).to include(blob.id)
      end

      it "compiled HTML references cid:blob-<id> for the attached image" do
        result = described_class.call(template)
        expect(result).to include("cid:blob-#{blob.id}")
      end

      it "compiled HTML does not contain active storage redirect URLs" do
        result = described_class.call(template)
        expect(result).not_to include("active_storage")
      end
    end

    context "with a rich_text body containing Lexxy highlight colors" do
      let(:template) do
        rich_text_template(
          '<p><mark style="color: var(--highlight-3);">red text</mark> ' \
          '<mark style="background-color: var(--highlight-bg-6);">blue bg</mark></p>'
        )
      end

      it "resolves text highlight variables to concrete colors" do
        result = described_class.call(template)
        expect(result).to include("color: rgb(207, 0, 0)")
      end

      it "resolves background highlight variables to concrete colors" do
        result = described_class.call(template)
        expect(result).to include("background-color: rgba(124, 192, 252, 0.3)")
      end

      it "leaves no var(--highlight…) references behind" do
        result = described_class.call(template)
        expect(result).not_to match(/var\(\s*--highlight/)
      end
    end
  end

  describe ".cids_to_blob_urls" do
    let_it_be(:blob) do
      Current.set(customer: customer) do
        ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("fake image data"),
          filename: "hero.png",
          content_type: "image/png"
        )
      end
    end

    it "swaps cid:blob-<id> sources for the blob's app-relative URL" do
      html = %(<p>hi</p><img src="cid:blob-#{blob.id}" alt="hero.png">)
      result = described_class.cids_to_blob_urls(html, customer_id: customer.id)
      expect(result).to include(Rails.application.routes.url_helpers.rails_blob_url(blob, only_path: true))
      expect(result).not_to include("cid:blob-")
    end

    it "leaves unknown blob ids untouched" do
      html = %(<img src="cid:blob-0" alt="gone.png">)
      expect(described_class.cids_to_blob_urls(html, customer_id: customer.id)).to eq(html)
    end

    it "does not mint a URL for another customer's blob" do
      other = create(:customer)
      foreign = Current.set(customer: other) do
        ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("other image"),
          filename: "other.png",
          content_type: "image/png"
        )
      end
      html = %(<img src="cid:blob-#{foreign.id}" alt="other.png">)

      expect(described_class.cids_to_blob_urls(html, customer_id: customer.id)).to eq(html)
    end

    it "returns blank input unchanged" do
      expect(described_class.cids_to_blob_urls(nil, customer_id: customer.id)).to be_nil
      expect(described_class.cids_to_blob_urls("", customer_id: customer.id)).to eq("")
    end
  end

  describe ".wrap_for_browser" do
    it "wraps a fragment in a full HTML document with base email preview styles" do
      result = described_class.wrap_for_browser("<p>Hi</p>")
      expect(result).to include("<!DOCTYPE html>")
      expect(result).to include("<body><p>Hi</p></body>")
      expect(result).to include("font-family:")
      expect(result).to include("img { max-width: 100%")
    end

    it "returns blank input unchanged" do
      expect(described_class.wrap_for_browser(nil)).to be_nil
      expect(described_class.wrap_for_browser("")).to eq("")
    end
  end

  describe ".for_browser" do
    let(:table_html) do
      '<figure class="lexxy-content__table-wrapper"><table><tbody>' \
        '<tr><th class="lexxy-content__table-cell--header"><p>H1</p></th>' \
        '<td><p>cell</p></td></tr></tbody></table></figure>'
    end

    it "compiles, rewrites cids, and wraps for an author-facing iframe" do
      blob = Current.set(customer: customer) do
        ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("fake image data"),
          filename: "hero.png",
          content_type: "image/png"
        )
      end
      template = rich_text_template(
        %(<div>#{ActionText::Attachment.from_attachable(blob)}#{table_html}</div>)
      )
      template.update_columns(body_html: table_html)

      result = described_class.for_browser(template)

      expect(result).to include("<!DOCTYPE html>")
      expect(result).to include("border-collapse: collapse")
      expect(result).to include(Rails.application.routes.url_helpers.rails_blob_url(blob, only_path: true))
      expect(result).not_to include("cid:blob-")
    end
  end

  describe "style merging" do
    it "does not emit doubled trailing semicolons on table styles" do
      template = rich_text_template(
        '<figure class="lexxy-content__table-wrapper"><table><tbody>' \
          '<tr><td><p>x</p></td></tr></tbody></table></figure>'
      )
      result = described_class.call(template)
      expect(result).not_to match(/;;/)
      expect(result).to match(/border-collapse: collapse; width: 100%;"/)
    end
  end
end
