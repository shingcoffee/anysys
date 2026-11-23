# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::TemplateTokenCodec do
  let_it_be(:customer) { create(:customer) }
  let!(:token) do
    Emails::TemplateToken.find_or_create_by!(
      customer_id: nil,
      source_type: Emails::TemplateToken::SOURCE_PLATFORM,
      source_key: "authentication_user.first_name"
    ) { |t| t.label = "First name" }
  end
  let(:uuid) { token.uuid }
  let(:label) { token.display_label }
  let(:catalog) { Emails::TokenCatalog.for_customer(customer.id) }

  describe ".tokens_to_labels" do
    it "rewrites UUID tokens to human-readable labels" do
      expect(described_class.tokens_to_labels("Hi {{#{uuid}}}", catalog: catalog))
        .to eq("Hi {{#{label}}}")
    end

    it "never exposes an unknown UUID in the editor" do
      unknown = "22222222-2222-4222-8222-222222222222"
      expect(described_class.tokens_to_labels("Hi {{#{unknown}}}", catalog: catalog))
        .to eq("Hi {{#{I18n.t("email.template_tokens.unknown_label")}}}")
    end

    it "preserves fallback text through the label round trip" do
      source = %(Hi {{#{uuid}|fallback:"Friend & <Guest>"}})
      displayed = described_class.tokens_to_labels(source, catalog: catalog)

      expect(displayed).to eq(%(Hi {{#{label}|fallback:"Friend & <Guest>"}}))
      expect(described_class.labels_to_tokens(displayed, customer_id: customer.id)).to eq(source)
    end
  end

  describe ".labels_to_tokens" do
    it "rewrites human-readable labels to UUID tokens" do
      expect(described_class.labels_to_tokens("Hi {{#{label}}}", customer_id: customer.id))
        .to eq("Hi {{#{uuid}}}")
    end

    it "leaves unknown labels unchanged" do
      expect(described_class.labels_to_tokens("Hi {{Unknown}}", customer_id: customer.id))
        .to eq("Hi {{Unknown}}")
    end
  end

  describe ".normalize_for_storage" do
    it "converts chip markup and labels to UUID tokens" do
      chip = described_class.chip_html(uuid, label)
      expect(described_class.normalize_for_storage("Hi #{chip} and {{#{label}}}", customer_id: customer.id))
        .to eq("Hi {{#{uuid}}} and {{#{uuid}}}")
    end

    it "leaves plain text ampersands and angle brackets byte-identical" do
      text = "R&D <Guest> 1 < 2 > 0 & email-token-chip {{#{label}}}"
      expect(described_class.normalize_for_storage(text, customer_id: customer.id))
        .to eq("R&D <Guest> 1 < 2 > 0 & email-token-chip {{#{uuid}}}")
    end

    it "continues to parse HTML when explicitly requested" do
      chip = described_class.chip_html(uuid, label)
      html = "<p>R&amp;D #{chip}</p>"
      expect(described_class.normalize_for_storage(html, customer_id: customer.id, format: :html))
        .to eq("<p>R&amp;D {{#{uuid}}}</p>")
    end

    it "preserves a chip's fallback including an empty fallback" do
      ["Friend & <Guest>", ""].each do |fallback|
        source = %({{#{uuid}|fallback:"#{fallback}"}})
        chip = described_class.tokens_to_chips(source, customer_id: customer.id)
        expect(described_class.normalize_for_storage(chip, customer_id: customer.id)).to eq(source)
      end
    end
  end

  describe "ambiguous labels" do
    let!(:custom) { create(:email_template_token, customer: customer, label: label.upcase) }

    it "does not silently map an unqualified colliding label to the custom token" do
      expect(described_class.labels_to_tokens("{{#{label}}}", customer_id: customer.id)).to eq("{{#{label}}}")
    end

    it "round-trips both qualified platform and custom labels to their own UUIDs" do
      [token, custom].each do |row|
        source = "{{#{row.uuid}}}"
        displayed = described_class.tokens_to_labels(source, catalog: catalog)
        expect(displayed).not_to include(row.uuid)
        expect(described_class.labels_to_tokens(displayed, customer_id: customer.id)).to eq(source)
      end
    end
  end
end
