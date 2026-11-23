# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::AuthorPreview do
  let_it_be(:customer) { create(:customer) }
  let(:catalog) { Emails::TokenCatalog.for_customer(customer.id) }
  let(:token) { platform_token("first_name") }
  let(:label) { Emails::TemplateToken.platform.find_by!(uuid: platform_token_uuid("first_name")).display_label }

  describe ".call" do
    context "mode: :tokens" do
      let(:template) do
        create(:email_template, customer: customer, editor_type: "code",
               subject: "Hi #{token}",
               body_html: "<p>Dear #{token}</p>",
               body_text: "Dear #{token}")
      end

      it "returns labeled subject/body without interpolating sample values" do
        result = described_class.call(template, mode: :tokens, catalog: catalog)

        expect(result[:subject]).to eq("Hi {{#{label}}}")
        expect(result[:body_html]).to include("Dear {{#{label}}}")
        expect(result[:body_html]).not_to include(platform_token_uuid("first_name"))
        expect(result[:body_text]).to include("Dear {{#{label}}}")
        expect(result[:body_srcdoc]).to include("<!DOCTYPE html>")
        expect(result[:body_srcdoc]).to include("Dear {{#{label}}}")
      end

      it "rewrites cid: images and wraps for an iframe" do
        blob = Current.set(customer: customer) do
          ActiveStorage::Blob.create_and_upload!(
            io: StringIO.new("img"),
            filename: "hero.png",
            content_type: "image/png"
          )
        end
        template.update!(body_html: %(<p>Hi</p><img src="cid:blob-#{blob.id}">))

        result = described_class.call(template, mode: :tokens, catalog: catalog)
        blob_url = Rails.application.routes.url_helpers.rails_blob_url(blob, only_path: true)

        expect(result[:body_html]).to include(blob_url)
        expect(result[:body_html]).not_to include("cid:blob-")
        expect(result[:body_srcdoc]).to include(blob_url)
      end

      it "does not rewrite cid: images that belong to another customer" do
        other = create(:customer)
        foreign = Current.set(customer: other) do
          ActiveStorage::Blob.create_and_upload!(
            io: StringIO.new("img"),
            filename: "other.png",
            content_type: "image/png"
          )
        end
        template.update!(body_html: %(<p>Hi</p><img src="cid:blob-#{foreign.id}">))

        result = described_class.call(template, mode: :tokens, catalog: catalog)
        expect(result[:body_html]).to include("cid:blob-#{foreign.id}")
        expect(result[:body_html]).not_to include(
          Rails.application.routes.url_helpers.rails_blob_url(foreign, only_path: true)
        )
      end
    end

    context "mode: :sample" do
      let(:user) { create(:user, customer: customer, first_name: "Ada") }
      let(:template) do
        create(:email_template, customer: customer, editor_type: "code",
               subject: "Hi #{token}",
               body_html: "<p>Dear #{token}</p>")
      end

      it "interpolates variables into subject and body" do
        vars = Emails::VariableContext.for(user: user)
        result = described_class.call(template, mode: :sample, vars: vars)

        expect(result[:subject]).to eq("Hi Ada")
        expect(result[:body_html]).to include("Dear Ada")
        expect(result[:body_srcdoc]).to include("<!DOCTYPE html>")
        expect(result[:body_srcdoc]).to include("Dear Ada")
      end
    end

    it "rejects unknown modes" do
      template = build(:email_template, customer: customer)
      expect {
        described_class.call(template, mode: :nope)
      }.to raise_error(ArgumentError, /unknown mode/)
    end
  end
end
