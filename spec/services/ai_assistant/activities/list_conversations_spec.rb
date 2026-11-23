# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Activities::ListConversations do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:user) { create(:user, :admin, customer: customer) }

  def list(actor: user, tenant: customer)
    described_class.call(customer: tenant, user: actor)
  end

  before do
    Current.customer = customer
    enable_ai_assistant_module!(customer)
  end

  it "returns an empty pair of lists for an admin who has never chatted" do
    result = list

    expect(result).to be_success
    expect(result.http_status).to eq(200)
    expect(result.active).to eq([])
    expect(result.archived).to eq([])
    expect(result.errors).to eq([])
  end

  it "splits open threads from archived ones, most recent first" do
    older = create(:ai_assistant_conversation, customer: customer, user: user,
                                               last_active_at: 2.days.ago)
    newer = create(:ai_assistant_conversation, customer: customer, user: user,
                                               last_active_at: 1.hour.ago)
    filed = create(:ai_assistant_conversation, :archived, customer: customer, user: user,
                                                          last_active_at: 3.days.ago)

    result = list

    expect(result.active).to eq([ newer, older ])
    expect(result.archived).to eq([ filed ])
  end

  it "orders threads sharing a timestamp by id so paging is deterministic" do
    stamp = 1.hour.ago
    first = create(:ai_assistant_conversation, customer: customer, user: user, last_active_at: stamp)
    second = create(:ai_assistant_conversation, customer: customer, user: user, last_active_at: stamp)

    expect(list.active).to eq([ second, first ])
  end

  it "hides another user's threads in the same tenant" do
    other = create(:user, :admin, customer: customer)
    create(:ai_assistant_conversation, customer: customer, user: other)
    mine = create(:ai_assistant_conversation, customer: customer, user: user)

    expect(list.active).to eq([ mine ])
  end

  it "hides the same user's threads in another tenant" do
    other_tenant = create(:customer)
    create(:ai_assistant_conversation, customer: other_tenant, user: user)
    mine = create(:ai_assistant_conversation, customer: customer, user: user)

    expect(list.active).to eq([ mine ])
  end

  it "refuses when the module is not enabled for the tenant" do
    fm = FeatureModules::Module.find_by!(key: "ai_assistant")
    FeatureModules::CustomerAssignment.where(customer: customer, feature_module: fm).delete_all

    result = list

    expect(result).not_to be_success
    expect(result.http_status).to eq(403)
    expect(result.errors).to include(I18n.t("ai_assistant.errors.module_disabled"))
    expect(result.active).to eq([])
  end

  it "does not need a configured provider to list what already exists" do
    AiAssistant::ProviderSettings.delete_all
    mine = create(:ai_assistant_conversation, customer: customer, user: user)

    expect(list.active).to eq([ mine ])
  end
end
