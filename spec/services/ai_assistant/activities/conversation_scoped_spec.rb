# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Activities::ConversationScoped do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:user) { create(:user, :admin, customer: customer) }

  # Smallest thing that can include the module: the shared guard and the
  # resolution helpers are the unit under test, not any one activity's body.
  let(:harness_class) do
    Class.new do
      include AiAssistant::Activities::ConversationScoped

      const_set(:Result, Class.new(AiAssistant::Activities::Preflight::Result))

      attr_reader :customer, :user

      def initialize(customer:, user:)
        @customer = customer
        @user = user
      end
    end
  end
  let(:activity) { harness_class.new(customer: customer, user: user) }

  def conversation_for(owner, *traits, tenant: customer, **attrs)
    create(:ai_assistant_conversation, *traits, customer: tenant, user: owner, **attrs)
  end

  def mark_running(conversation)
    message = create(:ai_assistant_message, customer: conversation.customer, conversation: conversation)
    AiAssistant::Assistant::GenerationLifecycle.start!(conversation: conversation, user_message: message)
  end

  before do
    Current.customer = customer
    enable_ai_assistant_module!(customer)
  end

  describe "#preflight_failure" do
    it "passes a tenant with the module enabled" do
      expect(activity.preflight_failure).to be_nil
    end

    it "refuses a tenant that does not have the module" do
      fm = FeatureModules::Module.find_by!(key: "ai_assistant")
      FeatureModules::CustomerAssignment.where(customer: customer, feature_module: fm).delete_all

      failure = activity.preflight_failure

      expect(failure.http_status).to eq(403)
      expect(failure.errors).to include(I18n.t("ai_assistant.errors.module_disabled"))
    end

    # Listing, naming, archiving and deleting a thread cost no vendor call, so
    # the provider check and the chat throttle are deliberately not run here.
    it "does not consult the provider or the rate limiter" do
      expect(AiAssistant::ProviderSettings).not_to receive(:active_for)
      expect(Authentication::Throttle).not_to receive(:new)

      expect(activity.preflight_failure).to be_nil
    end

    it "reports the including activity's contract errors as 422" do
      failing = Class.new(harness_class) do
        def contract_valid? = false
        def contract_errors = [ "Title can't be blank" ]
      end

      failure = failing.new(customer: customer, user: user).preflight_failure

      expect(failure.http_status).to eq(422)
      expect(failure.errors).to eq([ "Title can't be blank" ])
    end

    it "takes no contract by default" do
      expect(activity.contract_valid?).to be true
      expect(activity.contract_errors).to eq([])
    end
  end

  # 404, not 403: the caller learns nothing about whether the id exists in
  # someone else's history.
  describe "#not_found_failure" do
    it "is a 404 carrying the not-found copy" do
      failure = activity.not_found_failure

      expect(failure.success?).to be_falsey
      expect(failure.http_status).to eq(404)
      expect(failure.errors).to eq([ I18n.t("ai_assistant.errors.conversation_not_found") ])
    end
  end

  describe "#resolve_named_conversation" do
    # Reading a blank id as "the current thread" would let an id-less request
    # mutate — or destroy — a thread the caller never asked for.
    it "refuses a blank id" do
      conversation_for(user)

      expect(activity.resolve_named_conversation(nil)).to be_nil
      expect(activity.resolve_named_conversation("")).to be_nil
      expect(activity.resolve_named_conversation("   ")).to be_nil
    end

    it "creates nothing for a blank id" do
      expect { activity.resolve_named_conversation(nil) }
        .not_to change(AiAssistant::Conversation, :count)
    end

    it "returns the caller's own thread" do
      mine = conversation_for(user)

      expect(activity.resolve_named_conversation(mine.id)).to eq(mine)
    end

    it "refuses another user's thread in the same tenant" do
      other = create(:user, :admin, customer: customer)
      foreign = conversation_for(other)

      expect(activity.resolve_named_conversation(foreign.id)).to be_nil
    end

    it "refuses a thread in another tenant" do
      other_tenant = create(:customer)
      cross = create(:user, :admin, customer: other_tenant)
      foreign = conversation_for(cross, tenant: other_tenant)

      expect(activity.resolve_named_conversation(foreign.id)).to be_nil
    end

    it "refuses an id that does not exist" do
      expect(activity.resolve_named_conversation(999_999)).to be_nil
    end
  end

  describe "#resolve_conversation" do
    it "reads a blank id as the current thread, creating it on demand" do
      resolved = nil

      expect { resolved = activity.resolve_conversation(nil) }
        .to change(AiAssistant::Conversation, :count).by(1)
      expect(resolved.user).to eq(user)
      expect(resolved.customer).to eq(customer)
    end

    it "returns the caller's own named thread" do
      mine = conversation_for(user)

      expect(activity.resolve_conversation(mine.id)).to eq(mine)
    end

    it "refuses a thread in another tenant" do
      other_tenant = create(:customer)
      cross = create(:user, :admin, customer: other_tenant)
      foreign = conversation_for(cross, tenant: other_tenant)

      expect(activity.resolve_conversation(foreign.id)).to be_nil
    end
  end

  # Stop and the round-cap precheck run before the request is known to be
  # allowed, so they must not materialise a thread as a side effect.
  describe "#existing_conversation" do
    it "creates nothing for a blank id when the user has never chatted" do
      result = nil

      expect { result = activity.existing_conversation(nil) }
        .not_to change(AiAssistant::Conversation, :count)
      expect(result).to be_nil
    end

    it "creates nothing for a named id that does not exist" do
      expect { activity.existing_conversation(999_999) }
        .not_to change(AiAssistant::Conversation, :count)
    end

    it "returns the caller's own named thread" do
      mine = conversation_for(user)

      expect(activity.existing_conversation(mine.id)).to eq(mine)
    end

    it "refuses another user's thread in the same tenant" do
      other = create(:user, :admin, customer: customer)
      foreign = conversation_for(other)

      expect(activity.existing_conversation(foreign.id)).to be_nil
    end

    it "refuses a thread in another tenant" do
      other_tenant = create(:customer)
      cross = create(:user, :admin, customer: other_tenant)
      foreign = conversation_for(cross, tenant: other_tenant)

      expect(activity.existing_conversation(foreign.id)).to be_nil
    end

    it "reads a blank id as whatever is running" do
      conversation_for(user, last_active_at: 1.minute.ago)
      running = conversation_for(user, last_active_at: 2.days.ago)
      mark_running(running)

      expect(activity.existing_conversation(nil)).to eq(running)
    end
  end

  # An id-less stop means "whatever is running". That is usually the most
  # recently active thread, but not always: a reply still streaming into an
  # older thread would otherwise be left running while a newer, idle thread
  # was cancelled in its place.
  describe "#running_or_latest" do
    let(:scope) { AiAssistant::Conversation.owned_by(customer: customer, user: user) }

    it "prefers a running thread over a more recently active idle one" do
      conversation_for(user, last_active_at: 1.minute.ago)
      running = conversation_for(user, last_active_at: 3.days.ago)
      mark_running(running)

      expect(activity.running_or_latest(scope)).to eq(running)
    end

    it "prefers the most recently active of two running threads" do
      older = conversation_for(user, last_active_at: 3.days.ago)
      newer = conversation_for(user, last_active_at: 1.hour.ago)
      mark_running(older)
      mark_running(newer)

      expect(activity.running_or_latest(scope)).to eq(newer)
    end

    it "falls back to the newest active thread when nothing is running" do
      conversation_for(user, last_active_at: 3.days.ago)
      newest = conversation_for(user, last_active_at: 1.hour.ago)

      expect(activity.running_or_latest(scope)).to eq(newest)
    end

    it "ignores archived threads in the fallback" do
      conversation_for(user, :archived, last_active_at: 1.minute.ago)
      active = conversation_for(user, last_active_at: 2.days.ago)

      expect(activity.running_or_latest(scope)).to eq(active)
    end

    it "is nil when the user has no threads at all" do
      expect(activity.running_or_latest(scope)).to be_nil
    end

    it "is nil when the user only has archived threads and nothing is running" do
      conversation_for(user, :archived)

      expect(activity.running_or_latest(scope)).to be_nil
    end

    it "never reaches another user's running thread" do
      other = create(:user, :admin, customer: customer)
      mark_running(conversation_for(other))

      expect(activity.running_or_latest(scope)).to be_nil
    end

    # Cancelling or finishing a turn leaves current_generation_id pointing at
    # the finished row, so "has a generation id" is not "is running". Reading
    # it that way would let a long-idle thread shadow the live one for ever.
    it "ignores a thread whose generation has already finished" do
      stale = conversation_for(user, last_active_at: 1.minute.ago)
      AiAssistant::Assistant::GenerationLifecycle.cancel!(conversation: stale.tap { |c| mark_running(c) })
      running = conversation_for(user, last_active_at: 3.days.ago)
      mark_running(running)

      expect(stale.reload.current_generation_id).to be_present
      expect(activity.running_or_latest(scope)).to eq(running)
    end

    # Archiving cancels the turn, so this should not arise — but an id-less
    # request must never act on a thread the user has put away regardless.
    it "ignores an archived thread even while its generation is running" do
      archived = conversation_for(user, :archived, last_active_at: 1.minute.ago)
      mark_running(archived)
      active = conversation_for(user, last_active_at: 2.days.ago)

      expect(activity.running_or_latest(scope)).to eq(active)
    end
  end

  describe "#broadcast_conversations" do
    before { allow(AiAssistant::Stream).to receive(:broadcast_conversations) }

    it "refreshes the sidebar on the caller's own user stream" do
      activity.broadcast_conversations(current_id: 7)

      expect(AiAssistant::Stream).to have_received(:broadcast_conversations)
        .with(customer: customer, user: user, current_id: 7)
    end

    it "highlights nothing when no thread is current" do
      activity.broadcast_conversations

      expect(AiAssistant::Stream).to have_received(:broadcast_conversations)
        .with(customer: customer, user: user, current_id: nil)
    end
  end
end
