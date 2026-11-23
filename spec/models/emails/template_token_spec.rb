# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::TemplateToken, type: :model do
  let(:customer) { create(:customer) }

  describe "platform seeds" do
    it "seeds unsubscribe_url with a SecureRandom UUID" do
      row = described_class.platform.find_by!(source_key: "unsubscribe_url")
      expect(row.uuid).to match(described_class::UUID_REGEXP)
      expect(row.display_label).to eq("Unsubscribe URL")
    end

    it "localizes unsubscribe_url in zh-CN" do
      row = described_class.platform.find_by!(source_key: "unsubscribe_url")
      I18n.with_locale(:"zh-CN") do
        expect(row.display_label).to eq("退订链接")
      end
    end
  end

  describe "#display_label" do
    legacy_fields = {
      "payments_dispute.provider" => ["Dispute.provider", "Payment dispute provider", "支付争议服务商"],
      "payments_dispute.psp_dispute_id" => ["Dispute.psp_dispute_id", "Payment dispute provider's dispute ID", "支付争议服务商争议 ID"],
      "payments_dispute.raw" => ["Dispute.raw", "Payment dispute raw data", "支付争议原始数据"],
      "authentication_event.id" => ["Event.id", "Authentication event ID", "身份验证事件 ID"],
      "authentication_trusted_device.id" => ["TrustedDevice.id", "Trusted device ID", "受信任设备 ID"],
      "authentication_user.first_name" => ["User.first_name", "Recipient first name", "收件人名"],
      "authentication_user.last_name" => ["User.last_name", "Recipient last name", "收件人姓"],
      "unsubscribe_url" => ["unsubscribe_url", "Unsubscribe URL", "退订链接"]
    }

    legacy_fields.each do |source_key, (label, english, chinese)|
      it "uses the source key to label legacy #{source_key} rows in both locales" do
        token = described_class.new(source_type: described_class::SOURCE_PLATFORM, source_key: source_key, label: label)

        expect(I18n.with_locale(:en) { token.display_label }).to eq(english)
        expect(I18n.with_locale(:"zh-CN") { token.display_label }).to eq(chinese)
      end
    end

    it "uses common.labels for a known attribute instead of humanizing" do
      token = described_class.new(
        source_type: described_class::SOURCE_PLATFORM,
        source_key: "authentication_user.email",
        label: "User.email"
      )
      expect(token.display_label).to eq(I18n.t("common.labels.email"))
      I18n.with_locale(:"zh-CN") do
        expect(token.display_label).to eq("邮箱")
      end
    end

    it "gives an unrecognized platform label a distinctive readable localized fallback" do
      token = described_class.new(
        source_type: described_class::SOURCE_PLATFORM,
        source_key: "fraud.provider",
        label: "Fraud.provider"
      )
      expect(token.display_label).to eq("Other field: Fraud Provider")
      I18n.with_locale(:"zh-CN") do
        expect(token.display_label).to eq("其他字段：Fraud Provider")
      end
    end

    it "formats an unknown source when the stored label is blank" do
      token = described_class.new(source_type: described_class::SOURCE_PLATFORM, source_key: "custom_event.case_number", label: nil)
      expect(token.display_label).to eq("Other field: Custom Event Case Number")
    end

    it "keeps the translated platform keys in parity across locales" do
      english = I18n.t("email.template_tokens.platform", locale: :en)
      chinese = I18n.t("email.template_tokens.platform", locale: :"zh-CN")

      expect(english.keys).to match_array(chinese.keys)
      english.each do |group, fields|
        expect(fields.keys).to match_array(chinese.fetch(group).keys) if fields.is_a?(Hash)
      end
    end

    it "keeps custom labels as authored" do
      token = build(:email_template_token, customer: customer, label: "Member name")
      expect(token.display_label).to eq("Member name")
    end
  end

  describe "uuid assignment" do
    it "assigns SecureRandom.uuid on create when blank" do
      allow(SecureRandom).to receive(:uuid).and_return("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
      token = create(:email_template_token, customer: customer, uuid: nil)
      expect(token.uuid).to eq("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
    end
  end

  describe "custom validations" do
    it "accepts a customer entity attribute binding" do
      token = build(:email_template_token, customer: customer)
      expect(token).to be_valid
    end

    it "rejects an unknown attribute slug" do
      token = build(:email_template_token, customer: customer, attribute_slug: "missing")
      expect(token).not_to be_valid
      expect(token.errors[:attribute_slug]).to be_present
    end

    it "rejects custom rows missing an entity binding" do
      token = build(:email_template_token, customer: customer)
      token.entity = nil
      token.entity_id = nil
      expect(token).not_to be_valid
      expect(token.errors[:entity_id]).to be_present
    end

    it "rejects a nonblank entity ID that does not exist" do
      token = build(:email_template_token, customer: customer)
      token.entity_id = Entity.maximum(:id).to_i + 1

      expect(token).not_to be_valid
      expect(token.errors[:entity_id]).to include(I18n.t("email.template_tokens.errors.entity_not_accessible"))
    end
  end

  describe ".accessible_for" do
    it "returns platform rows plus the tenant's customs" do
      mine = create(:email_template_token, customer: customer)
      other = create(:email_template_token, customer: create(:customer))
      ids = described_class.accessible_for(customer.id).pluck(:id)
      expect(ids).to include(mine.id)
      expect(ids).not_to include(other.id)
      expect(described_class.accessible_for(customer.id).platform.count).to eq(described_class.platform.count)
    end
  end
end
