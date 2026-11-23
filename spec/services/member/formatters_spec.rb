# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::Formatters do
  describe ".format" do
    it "renders :string by escaping HTML" do
      expect(described_class.format("<b>x</b>", :string)).to eq("&lt;b&gt;x&lt;/b&gt;")
    end

    it "renders :date with the long format" do
      d = Date.new(2026, 5, 23)
      expect(described_class.format(d, :date)).to eq(I18n.l(d, format: :long))
    end

    it "renders :datetime with the long format" do
      t = Time.utc(2026, 5, 23, 10, 0)
      expect(described_class.format(t, :datetime)).to eq(I18n.l(t, format: :long))
    end

    it "renders :money from integer cents" do
      expect(described_class.format(1234, :money)).to include("$12.34")
    end

    it "renders :money with the given ISO currency from minor units" do
      expect(described_class.format({ amount: 1000, currency: "JPY" }, :money)).to eq("¥1000")
    end

    it "renders :money_large with the given ISO currency from minor units" do
      out = described_class.format({ amount: 1000, currency: "JPY" }, :money_large)
      expect(out).to include("text-3xl")
      expect(out).to include("¥1000")
      expect(out).not_to include("$")
    end

    it "renders :money_major with the given ISO currency" do
      expect(described_class.format({ amount: 1000, currency: "JPY" }, :money_major)).to eq("¥1000")
    end

    it "renders :money_major_large with the given ISO currency" do
      out = described_class.format({ amount: 31.5, currency: "CNY" }, :money_major_large)
      expect(out).to include("text-3xl")
      expect(out).to include("¥31.50")
    end

    it "renders :money_large with hero classes" do
      out = described_class.format(1234, :money_large)
      expect(out).to include("text-3xl")
      expect(out).to include("font-mono")
      expect(out).to include("$12.34")
    end

    it "renders :number as the value" do
      expect(described_class.format(42, :number)).to eq("42")
    end

    it "renders :number_large with hero classes" do
      out = described_class.format(42, :number_large)
      expect(out).to include("text-3xl")
      expect(out).to include("42")
    end

    it "renders :status_pill with a tone class" do
      out = described_class.format("succeeded", :status_pill)
      expect(out).to include("badge-success")
      expect(out).to include(I18n.t("common.status.succeeded"))
    end

    it "uses a generic pending label in zh-CN, not the email-oriented 待发送" do
      I18n.with_locale(:"zh-CN") do
        out = described_class.format("pending", :status_pill)
        expect(out).to include("待处理")
        expect(out).not_to include("待发送")
      end
    end

    it "uses a generic processing label in zh-CN, not the email-oriented 发送中" do
      I18n.with_locale(:"zh-CN") do
        out = described_class.format("processing", :status_pill)
        expect(out).to include("处理中")
        expect(out).not_to include("发送中")
      end
    end

    it "renders :status_pill default tone for unknown values" do
      out = described_class.format("weird", :status_pill)
      expect(out).to include("badge-default")
      expect(out).to include("weird")
    end

    it "does not translate an unknown status through a colliding common.status key" do
      out = described_class.format("draft", :status_pill)
      expect(out).to include("draft")
      expect(out).not_to include(I18n.t("common.status.draft"))
    end

    it "renders :mono with font-mono and break-all" do
      out = described_class.format("ABC123", :mono)
      expect(out).to include("font-mono")
      expect(out).to include("break-all")
      expect(out).to include("ABC123")
    end

    it "renders nil values as an empty string" do
      expect(described_class.format(nil, :string)).to eq("")
    end

    it "raises on unknown format keys" do
      expect { described_class.format("x", :unknown) }.to raise_error(ArgumentError, /unknown format/)
    end

    it "returns html_safe strings for HTML formats" do
      expect(described_class.format(1234, :money_large)).to be_html_safe
      expect(described_class.format("succeeded", :status_pill)).to be_html_safe
      expect(described_class.format("ABC", :mono)).to be_html_safe
    end
  end
end
