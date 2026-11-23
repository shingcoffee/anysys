# frozen_string_literal: true

require "rails_helper"
require "yaml"

RSpec.describe FlowchartRuntime::Step do
  def flatten_keys(hash, prefix = nil)
    hash.each_with_object([]) do |(key, value), keys|
      path = prefix ? "#{prefix}.#{key}" : key.to_s
      if value.is_a?(Hash)
        keys.concat(flatten_keys(value, path))
      else
        keys << path
      end
    end
  end

  let(:ctx) { {} }

  describe ".fail" do
    it "appends the translated message, records details, and returns false" do
      expect(described_class.fail(ctx, :record_not_found, field: :findValue)).to be(false)

      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.record_not_found")])
      expect(ctx[:error_details]).to eq([
        { "code" => "record_not_found", "field" => "findValue", "message" => "Record was not found.", "details" => {} }
      ])
    end

    it "stringifies detail values and skips a duplicate message" do
      described_class.fail(ctx, :http_status, status: 503)
      described_class.fail(ctx, :http_status, status: 503)

      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.http_status", status: 503)])
      expect(ctx[:error_details].size).to eq(2)
      expect(ctx[:error_details].first["details"]).to eq(status: "503")
    end

    it "resolves a dotted action-specific code in the request locale" do
      I18n.backend.store_translations(:en, {
        flowchart_runtime: { errors: { send_sms: { quota: "SMS quota exceeded (%{used}/%{limit})" } } }
      })
      I18n.backend.store_translations(:"zh-CN", {
        flowchart_runtime: { errors: { send_sms: { quota: "短信额度已用尽（%{used}/%{limit}）" } } }
      })

      I18n.with_locale(:"zh-CN") do
        described_class.fail(ctx, "send_sms.quota", used: 10, limit: 10)
      end

      expect(ctx[:errors]).to eq(["短信额度已用尽（10/10）"])
      expect(ctx[:error_details].first["code"]).to eq("send_sms.quota")
    end

    it "keeps Phase 2 collect output as unique Array<String>" do
      described_class.fail(ctx, :timed_out)
      described_class.fail(ctx, :timed_out)

      expect(FlowchartRuntime::Errors.collect(ctx)).to eq([I18n.t("flowchart_runtime.errors.timed_out")])
    end
  end

  describe ".fail_message" do
    it "appends the request-locale text with an English fallback" do
      localized = { "en" => "Not eligible", "zh-CN" => "不符合条件。" }

      I18n.with_locale(:"zh-CN") do
        expect(described_class.fail_message(ctx, localized)).to be(false)
      end
      expect(ctx[:errors]).to eq(["不符合条件。"])
      expect(ctx[:error_details].first["code"]).to eq("business_error")

      I18n.with_locale(:"zh-CN") do
        described_class.fail_message(ctx, { "en" => "Not eligible" }, code: :business_error)
      end
      expect(ctx[:errors]).to eq(["不符合条件。", "Not eligible"])
    end

    it "records an optional field on error_details" do
      described_class.fail_message(ctx, { "en" => "Bad email" }, field: :email)
      expect(ctx[:error_details].first).to include("code" => "business_error", "field" => "email")
    end

    it "interpolates variables and records a custom code" do
      described_class.fail_message(
        ctx,
        { "en" => "Used %{used}" },
        code: :quota_exceeded,
        variables: { used: 3 }
      )
      expect(ctx[:errors]).to eq(["Used 3"])
      expect(ctx[:error_details].first["code"]).to eq("quota_exceeded")
    end
  end


  describe ".attempt" do
    it "returns the block value when nothing is raised" do
      expect(described_class.attempt(ctx, :record_invalid, ActiveRecord::RecordInvalid) { :ok }).to eq(:ok)
      expect(ctx[:errors]).to be_nil
    end

    it "fails with the demodulized class as reason and keeps the exception out of ctx[:errors]" do
      expect(
        described_class.attempt(ctx, :transport_error, OutboundHttp::TransportError) do
          raise OutboundHttp::TransportError, "connection refused"
        end
      ).to be(false)

      expect(ctx[:errors]).to eq([
        I18n.t("flowchart_runtime.errors.transport_error", reason: "TransportError")
      ])
      expect(ctx[:errors].join).not_to include("connection refused")
      expect(ctx[:error_details].last["details"]).to eq(reason: "TransportError")
      expect(ctx[:error_details].last["diagnostic"]).to eq("connection refused")
    end

    it "propagates exceptions that are not listed" do
      expect {
        described_class.attempt(ctx, :transport_error, OutboundHttp::TransportError) { raise ArgumentError, "boom" }
      }.to raise_error(ArgumentError, "boom")
      expect(ctx[:errors]).to be_nil
    end
  end

  describe ".dig" do
    it "reads nested hashes with indifferent keys and arrays by integer index" do
      value = { "params" => { email: "a@x.io", items: [{ "name" => "One" }] } }

      expect(described_class.dig(value, :params, "email")).to eq("a@x.io")
      expect(described_class.dig(value, "params", :items, 0, :name)).to eq("One")
      expect(described_class.dig(value, :missing, :email)).to be_nil
      expect(described_class.dig(nil, :params)).to be_nil
    end

    it "reads a record's id and its stored and calculated values" do
      customer = create(:customer)
      entity = create(:entity, customer: customer, property_schema: [
        { "name" => "Price", "name_slug" => "price", "type" => "Float", "html_type" => "number" },
        { "name" => "Total", "name_slug" => "total", "type" => "Calculated", "html_type" => "number",
          "readonly" => true, "storage" => "computed", "formula" => "price * 2" }
      ].to_json)
      entry = create(:entity_entry, customer: customer, entity: entity, data: { price: 4 }.to_json)

      expect(described_class.dig({ model: entry }, :model, :price)).to eq(4)
      expect(described_class.dig({ model: entry }, :model, :total).to_f).to eq(8.0)
      expect(described_class.dig({ model: entry }, :model, :id)).to eq(entry.id)
      expect(FlowchartRuntime::Template.render("{{ model.total }} for #{entry.id == entry.to_liquid['id']}", { model: entry })).to eq("8 for true")
    end
  end

  it "keeps flowchart_runtime locale keys and interpolations in parity" do
    english = YAML.safe_load_file(Rails.root.join("config/locales/flowchart_runtime.en.yml"))
                  .fetch("en").fetch("flowchart_runtime")
    chinese = YAML.safe_load_file(Rails.root.join("config/locales/flowchart_runtime.zh-CN.yml"))
                  .fetch("zh-CN").fetch("flowchart_runtime")

    expect(flatten_keys(chinese).sort).to eq(flatten_keys(english).sort)
    english_errors = english.fetch("errors")
    chinese_errors = chinese.fetch("errors")
    english_errors.each do |key, value|
      next unless value.is_a?(String)

      expect(value.scan(/%\{(\w+)\}/).flatten).to eq(chinese_errors.fetch(key).scan(/%\{(\w+)\}/).flatten)
    end
  end
end
