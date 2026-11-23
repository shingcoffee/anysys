# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Subsystems::Preflight do
  let(:customer) { create(:customer) }
  let(:other) { create(:customer) }

  def plan(**attrs) = described_class::Plan.new(**attrs)
  def check(build, tenant: customer) = described_class.call(customer: tenant, plan: build)
  def room(item_key, tenant: customer) = Billing::Quota.for(tenant).remaining(item_key)
  def codes(issues) = issues.map(&:code)

  def authentication!(tenant, signup: false, status: :active)
    fm = find_or_create_feature_module!("authentication")
    fm.set_extendable_model!(EntityDefinitions::Capabilities::PERSON_MODEL, true)
    ensure_customer_feature_module(tenant, fm, status: status, configuration: { "allow_registration" => signup }.to_json)
  end

  it "passes a build that fits the plan and the workspace settings" do
    authentication!(customer, signup: true)
    result = check(plan(entities: room("entity"), pages: room("page"), logins: true, signup: true))

    expect(result.ok).to be(true)
    expect([result.blockers, result.warnings]).to eq([[], []])
  end

  it "blocks a build that needs more entities than the plan has room for" do
    needed = room("entity") + 1
    blocker = check(plan(entities: needed)).blockers.sole

    expect(blocker.code).to eq("entity_quota")
    expect(blocker.message).to eq(I18n.t("ai_assistant.subsystems.preflight.quota_exceeded",
                                         needed: needed, unit: I18n.t("comp_billing.countable_items.entity.unit"),
                                         remaining: needed - 1, limit: Billing::Quota.for(customer).limit("entity")))
  end

  it "blocks a build that needs more pages than the plan has room for" do
    result = check(plan(entities: 1, pages: room("page") + 1))

    expect(result.ok).to be(false)
    expect(codes(result.blockers)).to eq(["page_quota"])
  end

  it "never blocks the platform owner's workspace on quota" do
    platform = ensure_platform_customer

    expect(check(plan(entities: 10_000, pages: 10_000), tenant: platform).ok).to be(true)
  end

  it "blocks logins the workspace cannot give, and only when the build asks for them" do
    authentication!(customer, status: :suspended)

    expect(codes(check(plan(entities: 1, logins: true)).blockers)).to eq(["logins_unavailable"])
    expect(check(plan(entities: 1)).ok).to be(true)
  end

  it "warns, without blocking, that a sign-up journey stays a draft while sign-up is off" do
    authentication!(customer, signup: false)
    result = check(plan(entities: 1, logins: true, signup: true))

    expect(result.ok).to be(true)
    expect(result.warnings.map { |issue| [issue.code, issue.message] })
      .to eq([["signup_disabled", I18n.t("operations.journeys.sign_up_disabled")]])
    expect(check(plan(entities: 1, logins: true)).warnings).to be_empty
  end

  it "judges a workspace by its own usage and settings, never another customer's" do
    entity_room = room("entity")
    create_list(:entity, 2, customer: other)
    authentication!(other, signup: true)
    authentication!(customer, signup: false, status: :suspended)

    result = check(plan(entities: entity_room, logins: true, signup: true))

    expect(codes(result.blockers)).to eq(["logins_unavailable"])
    expect(check(plan(entities: entity_room)).ok).to be(true)
    expect(check(plan(entities: 1, logins: true, signup: true), tenant: other).ok).to be(true)
  end

  it "keeps the en and zh-CN messages in parity" do
    files = %w[en zh-CN].map { |locale| YAML.load_file(Rails.root.join("config/locales/ai_assistant_subsystems.#{locale}.yml")).fetch(locale) }
    flatten = lambda do |hash, prefix = nil|
      hash.flat_map { |key, value| value.is_a?(Hash) ? flatten.call(value, [prefix, key].compact.join(".")) : [[[prefix, key].compact.join("."), value]] }
    end
    english, chinese = files.map { |file| flatten.call(file).to_h }

    expect(chinese.keys).to match_array(english.keys)
    english.each { |key, value| expect(chinese[key].scan(/%\{\w+\}/).uniq.sort).to eq(value.scan(/%\{\w+\}/).uniq.sort), key }
  end
end
