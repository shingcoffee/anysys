# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::SendActivities::FieldCatalog do
  subject(:catalog) { described_class.new }

  it "exposes core User scalar fields" do
    fields = catalog.fields.map { |f| f[:field] }
    expect(fields).to include("email", "first_name", "last_name", "created_at", "status")
  end

  it "exposes fields from associations as <assoc>.<column>" do
    fields = catalog.fields.map { |f| f[:field] }
    # users has_many :roles (through users_roles); roles has a key column
    expect(fields).to include("roles.key")
  end

  it "marks each field with a value type and allowed operators" do
    email = catalog.fields.find { |f| f[:field] == "email" }
    expect(email[:type]).to eq(:string)
    expect(email[:operators]).to include("equals", "contains")

    created = catalog.fields.find { |f| f[:field] == "created_at" }
    expect(created[:operators]).to include("after", "before")
  end

  it "resolves a field to its association path + column, rejecting unknown fields" do
    expect(catalog.resolve("roles.key")).to eq(association: :roles, column: "key", type: :string)
    expect(catalog.resolve("email")).to eq(association: nil, column: "email", type: :string)
    expect(catalog.resolve("evil; DROP TABLE users; --")).to be_nil
    expect(catalog.resolve("roles.nonexistent")).to be_nil
  end

  it "does not expose credential or sign-in token columns as audience filters" do
    fields = catalog.fields.map { |f| f[:field] }
    expect(fields).not_to include(
      "encrypted_password", "otp_secret", "reset_password_token",
      "confirmation_token", "unlock_token", "sign_in_token"
    )
    expect(catalog.resolve("sign_in_token")).to be_nil
  end

  it "localizes known field labels instead of titleizing the column name" do
    email = catalog.fields.find { |f| f[:field] == "email" }
    expect(email[:label]).to eq(I18n.t("common.labels.email"))

    I18n.with_locale(:"zh-CN") do
      zh = described_class.new.fields.find { |f| f[:field] == "email" }
      expect(zh[:label]).to eq("邮箱")
    end
  end

  it "does not titleize an unknown field identifier" do
    label = catalog.send(:field_label, "foo_bar")
    expect(label).to eq("foo_bar")
  end
end
