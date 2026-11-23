# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::ExecutionPolicy do
  let(:customer) { create(:customer) }
  let(:user) { create(:user, :admin, customer: customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: user) }
  let(:message) { create(:ai_assistant_message, conversation: conversation, customer: customer) }
  let(:generation) do
    AiAssistant::Assistant::GenerationLifecycle.start!(
      conversation: conversation,
      user_message: message
    )
  end

  before { enable_ai_assistant!(customer) }

  it "allows an active same-tenant admin" do
    expect(described_class.call(generation: generation)).to be_allowed
  end

  it "rejects an inactive user" do
    generation
    user.update!(status: :inactive)

    result = described_class.call(generation: generation)

    expect(result).not_to be_allowed
    expect(result.error_code).to eq(:unauthorized)
  end

  it "rejects a member" do
    member = create(:user, :member, customer: customer)
    member_conversation = create(:ai_assistant_conversation, customer: customer, user: member)
    member_message = create(
      :ai_assistant_message,
      conversation: member_conversation,
      customer: customer
    )
    member_generation = AiAssistant::Assistant::GenerationLifecycle.start!(
      conversation: member_conversation,
      user_message: member_message
    )

    expect(described_class.call(generation: member_generation)).not_to be_allowed
  end

  it "rejects work after the module is disabled" do
    generation
    FeatureModules::CustomerAssignment.where(customer: customer).delete_all

    result = described_class.call(generation: generation)

    expect(result).not_to be_allowed
    expect(result.error_code).to eq(:module_disabled)
  end

  it "rejects a cross-tenant admin at job execution" do
    other_customer = create(:customer)
    other_admin = create(:user, :admin, customer: other_customer)
    cross_tenant_conversation = create(
      :ai_assistant_conversation,
      customer: customer,
      user: other_admin
    )
    cross_tenant_message = create(
      :ai_assistant_message,
      conversation: cross_tenant_conversation,
      customer: customer
    )
    cross_tenant_generation = AiAssistant::Assistant::GenerationLifecycle.start!(
      conversation: cross_tenant_conversation,
      user_message: cross_tenant_message
    )

    result = described_class.call(generation: cross_tenant_generation)

    expect(result).not_to be_allowed
    expect(result.error_code).to eq(:unauthorized)
  end

  it "allows the fixed platform owner to execute in another tenant" do
    owner = find_or_create_platform_owner
    owner_conversation = create(
      :ai_assistant_conversation,
      customer: customer,
      user: owner
    )
    owner_message = create(
      :ai_assistant_message,
      conversation: owner_conversation,
      customer: customer
    )
    owner_generation = AiAssistant::Assistant::GenerationLifecycle.start!(
      conversation: owner_conversation,
      user_message: owner_message
    )

    expect(described_class.call(generation: owner_generation)).to be_allowed
  end

  it "rejects a generation whose source row is not a user message" do
    assistant_message = create(
      :ai_assistant_message,
      :assistant,
      conversation: conversation,
      customer: customer
    )
    invalid_generation = AiAssistant::Assistant::GenerationLifecycle.start!(
      conversation: conversation,
      user_message: assistant_message
    )

    result = described_class.call(generation: invalid_generation)

    expect(result).not_to be_allowed
    expect(result.error_code).to eq(:invalid_context)
  end

  it "rejects queued work after its generation provider is deactivated" do
    generation
    AiAssistant::ProviderSettings.active_for(:generation).deactivate_for!(:generation)

    result = described_class.call(generation: generation)

    expect(result).not_to be_allowed
    expect(result.error_code).to eq(:unconfigured)
  end
end
