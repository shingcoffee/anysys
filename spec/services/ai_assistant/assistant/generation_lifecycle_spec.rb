# frozen_string_literal: true

require "rails_helper"
require "concurrent"

RSpec.describe AiAssistant::Assistant::GenerationLifecycle do
  let(:customer) { create(:customer) }
  let(:user) { create(:user, :admin, customer: customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: user) }

  def create_user_message(body)
    create(
      :ai_assistant_message,
      customer: customer,
      conversation: conversation,
      body: body
    )
  end

  describe ".start!" do
    it "creates a queued generation and makes it current" do
      user_message = create_user_message("Build a student entity")

      generation = described_class.start!(
        conversation: conversation,
        user_message: user_message
      )

      expect(generation).to have_attributes(
        customer_id: customer.id,
        conversation_id: conversation.id,
        user_message_id: user_message.id,
        status: "queued",
        started_at: nil,
        finished_at: nil,
        cancelled_at: nil
      )
      expect(generation.token).to be_present
      expect(conversation.reload.current_generation).to eq(generation)
    end

    it "supersedes the prior active generation" do
      first = described_class.start!(
        conversation: conversation,
        user_message: create_user_message("First request")
      )

      freeze_time do
        second = described_class.start!(
          conversation: conversation,
          user_message: create_user_message("Replacement request")
        )

        expect(first.reload).to have_attributes(
          status: "superseded",
          finished_at: Time.current
        )
        expect(conversation.reload.current_generation).to eq(second)
      end
    end

    it "rejects a cross-tenant message without disturbing the current generation" do
      current = described_class.start!(
        conversation: conversation,
        user_message: create_user_message("Current request")
      )
      other_customer = create(:customer)
      cross_tenant_message = create(
        :ai_assistant_message,
        customer: other_customer,
        conversation: conversation,
        body: "Wrong tenant"
      )

      expect {
        described_class.start!(
          conversation: conversation,
          user_message: cross_tenant_message
        )
      }.to raise_error(ActiveRecord::RecordInvalid)

      expect(current.reload.status).to eq("queued")
      expect(conversation.reload.current_generation).to eq(current)
      expect(conversation.generations.count).to eq(1)
    end
  end

  describe ".claim!" do
    it "reports a generation cancelled before it can be claimed" do
      generation = described_class.start!(
        conversation: conversation,
        user_message: create_user_message("Cancel me")
      )
      described_class.cancel!(conversation: conversation)

      expect(described_class.claim!(generation)).to eq(:cancelled)
    end

    it "reports a cancelled predecessor as stale after a replacement becomes current" do
      cancelled = described_class.start!(
        conversation: conversation,
        user_message: create_user_message("Cancel me")
      )
      described_class.cancel!(conversation: conversation)
      replacement = described_class.start!(
        conversation: conversation,
        user_message: create_user_message("Replacement")
      )

      expect(described_class.claim!(cancelled)).to eq(:stale)
      expect(cancelled.reload.status).to eq("cancelled")
      expect(conversation.reload.current_generation).to eq(replacement)
    end
  end

  describe ".claim! with competing connections" do
    self.use_transactional_tests = false

    before do
      @customer = create(:customer)
      @user = create(:user, :admin, customer: @customer)
      @conversation = create(
        :ai_assistant_conversation,
        customer: @customer,
        user: @user
      )
      @user_message = create(
        :ai_assistant_message,
        customer: @customer,
        conversation: @conversation,
        body: "Claim me"
      )
      @generation = described_class.start!(
        conversation: @conversation,
        user_message: @user_message
      )
    end

    after do
      AiAssistant::Generation.where(conversation_id: @conversation.id).delete_all
      AiAssistant::Message.where(conversation_id: @conversation.id).delete_all
      AiAssistant::Conversation.where(id: @conversation.id).delete_all
      @user.destroy!
      @customer.destroy!
      ActiveRecord::Base.connection_handler.clear_all_connections!
    end

    it "allows exactly one simultaneous claimant to transition the generation" do
      barrier = Concurrent::CyclicBarrier.new(3)
      results = Queue.new
      threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            contender = AiAssistant::Generation.find(@generation.id)
            raise "claim barrier timed out" unless barrier.wait(5)

            results << described_class.claim!(contender)
          rescue StandardError => e
            results << e
          ensure
            Current.reset
          end
        end
      end

      raise "claim barrier timed out" unless barrier.wait(5)
      threads.each(&:join)
      outcomes = 2.times.map { results.pop }

      expect(outcomes).to contain_exactly(:claimed, :stale)
      expect(@generation.reload.status).to eq("running")
      expect(@generation.started_at).to be_present
    end
  end

  describe ".cancel!" do
    it "cancels the current running generation" do
      generation = described_class.start!(
        conversation: conversation,
        user_message: create_user_message("Stop this")
      )
      described_class.claim!(generation)

      freeze_time do
        expect(described_class.cancel!(conversation: conversation)).to eq(generation)
        expect(generation.reload).to have_attributes(
          status: "cancelled",
          cancelled_at: Time.current,
          finished_at: Time.current
        )
      end
    end
  end

  describe ".finish!" do
    it "records the terminal result and clears its own current pointer" do
      generation = described_class.start!(
        conversation: conversation,
        user_message: create_user_message("Finish me")
      )
      described_class.claim!(generation)

      freeze_time do
        pointer_cleared = described_class.finish!(
          generation,
          status: :failed,
          failure_code: "provider_unavailable"
        )

        expect(generation.reload).to have_attributes(
          status: "failed",
          failure_code: "provider_unavailable",
          finished_at: Time.current
        )
        expect(conversation.reload.current_generation).to be_nil
        expect(pointer_cleared).to eq(true)
      end
    end

    it "does not overwrite a superseded result or clear a newer generation pointer" do
      first = described_class.start!(
        conversation: conversation,
        user_message: create_user_message("First request")
      )
      second = described_class.start!(
        conversation: conversation,
        user_message: create_user_message("Second request")
      )

      pointer_cleared = described_class.finish!(first, status: :completed)

      expect(first.reload.status).to eq("superseded")
      expect(conversation.reload.current_generation).to eq(second)
      expect(pointer_cleared).to eq(false)
    end

    it "never executes caller publication work while finishing" do
      generation = described_class.start!(
        conversation: conversation,
        user_message: create_user_message("Finish without publishing")
      )
      described_class.claim!(generation)
      published = false

      pointer_cleared = described_class.finish!(generation, status: :completed) do
        published = true
      end

      expect(pointer_cleared).to eq(true)
      expect(published).to eq(false)
    end
  end
end
