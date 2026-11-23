# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::PasswordEffects do
  self.use_transactional_tests = false

  let(:customer) { create(:customer) }
  let(:other_customer) { create(:customer) }
  let(:user) { create(:user, customer: customer) }

  before do
    raise "This spec requires real transaction boundaries" if ActiveRecord::Base.connection.transaction_open?
    user
    other_customer
  end

  after do
    Authentication::User.find_by(id: user.id)&.destroy!
    customer.destroy!
    other_customer.destroy!
  end

  def check(password, customer_id: customer.id)
    FlowchartRuntime::Authentication.password(user: user, password: password, customer_id: customer_id)
  end

  # The first callback models an account update that wins the gap between the
  # business rollback and the security replay, without sleeps or mocked rows.
  def rollback(after_rollback: nil)
    ActiveRecord::Base.transaction do |transaction|
      transaction.after_rollback(&after_rollback) if after_rollback
      described_class.transaction(customer_id: customer.id) { yield }
      raise ActiveRecord::Rollback
    end
  end

  # Each level is a real transaction/savepoint. PasswordEffects joins the
  # innermost level; its callbacks must survive every ancestor's disposition.
  def nested_transactions(outcomes, depth = 0, &work)
    ActiveRecord::Base.transaction(requires_new: depth.positive?) do
      if depth == outcomes.length - 1
        described_class.transaction(customer_id: customer.id, &work)
      else
        nested_transactions(outcomes, depth + 1, &work)
      end
      raise ActiveRecord::Rollback if outcomes[depth] == :rollback
    end
  end

  describe "nested savepoint finalization" do
    [2, 3].each do |levels|
      %i[commit rollback].repeated_permutation(levels).each do |outcomes|
        it "persists one attempt and sends one unlock notification for #{outcomes.join(' / ')}" do
          allow(Authentication::User).to receive(:maximum_attempts).and_return(1)
          allow(Authentication::User).to receive(:unlock_strategy).and_return(:both)
          delivery = instance_double(ActionMailer::MessageDelivery, deliver_later: true)
          expect(Devise.mailer).to receive(:unlock_instructions).once do |account, token, _options|
            expect(ActiveRecord::Base.current_transaction).not_to be_open
            expect(account.id).to eq(user.id)
            expect(user.reload.unlock_token).to eq(Devise.token_generator.digest(Authentication::User, :unlock_token, token))
            delivery
          end

          nested_transactions(outcomes) { expect(check("wrong")).to be_nil }

          expect(ActiveRecord::Base.current_transaction).not_to be_open
          expect(user.reload.failed_attempts).to eq(1)
          expect(user).to be_access_locked
          expect(described_class::Scope.journal).to be_nil
        end

        it "preserves a successful reset for #{outcomes.join(' / ')}" do
          user.update!(failed_attempts: 3)
          nested_transactions(outcomes) { expect(check("password123")).to eq(user) }
          expect(user.reload.failed_attempts).to eq(0)
        end
      end
    end

    it "defers rolled-back effects while an ancestor is still open" do
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.transaction(requires_new: true) do
          described_class.transaction(customer_id: customer.id) { check("wrong") }
          raise ActiveRecord::Rollback
        end
        expect(ActiveRecord::Base.current_transaction).to be_open
        expect(user.reload.failed_attempts).to eq(0)
      end
      expect(user.reload.failed_attempts).to eq(1)
    end

    it "preserves effect order through successive ancestor rollbacks" do
      nested_transactions([:rollback, :rollback, :rollback]) do
        check("wrong")
        check("password123")
        check("wrong-again")
      end
      expect(user.reload.failed_attempts).to eq(1)
    end

    it "preserves the original exception and the security effect when all ancestors roll back" do
      expect {
        nested_transactions([:commit, :commit, :commit]) do
          check("wrong")
          raise "nested business failure"
        end
      }.to raise_error("nested business failure")
      expect(user.reload.failed_attempts).to eq(1)
      expect(described_class::Scope.journal).to be_nil
    end

    it "persists effects when a nested exception is rescued and the parent commits" do
      ActiveRecord::Base.transaction do
        begin
          nested_transactions([:commit, :commit]) do
            check("wrong")
            raise "rescued business failure"
          end
        rescue RuntimeError => e
          expect(e.message).to eq("rescued business failure")
        end
      end
      expect(user.reload.failed_attempts).to eq(1)
    end

    it "retains an effect if its final persistence transaction fails" do
      journal = nil
      replaying = false
      allow(Authentication::User).to receive(:increment_counter).and_wrap_original do |original, *args, **options|
        raise ActiveRecord::StatementInvalid, "security write failed" if replaying

        original.call(*args, **options)
      end
      expect {
        rollback(after_rollback: -> { replaying = true }) do
          journal = described_class::Scope.journal
          check("wrong")
        end
      }.to raise_error(ActiveRecord::StatementInvalid, "security write failed")
      expect(user.reload.failed_attempts).to eq(0)

      replaying = false
      journal.replay!
      journal.replay!
      expect(user.reload.failed_attempts).to eq(1)
    end

    it "does not repeat a committed effect after a notification callback raises" do
      allow(Authentication::User).to receive(:maximum_attempts).and_return(1)
      allow(Authentication::User).to receive(:unlock_strategy).and_return(:both)
      delivery = instance_double(ActionMailer::MessageDelivery)
      allow(delivery).to receive(:deliver_later).and_raise(IOError, "mail unavailable")
      expect(Devise.mailer).to receive(:unlock_instructions).once.and_return(delivery)
      journal = nil

      expect {
        nested_transactions([:rollback, :rollback, :rollback]) do
          journal = described_class::Scope.journal
          check("wrong")
        end
      }.to raise_error(IOError, "mail unavailable")
      expect(user.reload.failed_attempts).to eq(1)
      journal.replay!
      expect(user.reload.failed_attempts).to eq(1)
    end
  end

  it "runs the real credential comparison once and replays only its outcome" do
    expect_any_instance_of(Authentication::User).to receive(:valid_password?).with("wrong").once.and_call_original
    rollback { expect(check("wrong")).to be_nil }
    expect(user.reload.failed_attempts).to eq(1)
    expect(described_class::Scope.journal).to be_nil
  end

  it "preserves comparison/reset order for multiple authentication steps" do
    rollback do
      expect(check("wrong")).to be_nil
      expect(check("password123")).to eq(user)
      expect(check("wrong-again")).to be_nil
    end
    expect(user.reload.failed_attempts).to eq(1)
  end

  it "replays through Devise against a concurrent increment instead of overwriting its counter" do
    concurrent_failure = -> { Authentication::PasswordVerification.call(user: user.reload, password: "another-wrong-password") }
    rollback(after_rollback: concurrent_failure) { expect(check("wrong")).to be_nil }
    expect(user.reload.failed_attempts).to eq(2)
  end

  ["wrong", "password123"].each do |password|
    it "discards a #{password == 'wrong' ? 'failed' : 'successful'} comparison when the password changes before replay" do
      changed_password = -> { user.reload.update!(password: "new-password123", failed_attempts: 7) }
      rollback(after_rollback: changed_password) { check(password) }
      expect(user.reload.failed_attempts).to eq(7)
      expect(user.valid_password?("new-password123")).to be(true)
    end
  end

  it "does not unlock or reset an account locked after a successful comparison" do
    locked_account = -> { user.reload.update!(locked_at: Time.current, failed_attempts: Authentication::User.maximum_attempts) }
    rollback(after_rollback: locked_account) { expect(check("password123")).to eq(user) }
    expect(user.reload).to be_access_locked
    expect(user.failed_attempts).to be >= Authentication::User.maximum_attempts
  end

  it "rechecks tenant ownership after rollback" do
    moved_account = -> { user.reload.update!(customer_id: other_customer.id, failed_attempts: 4) }
    rollback(after_rollback: moved_account) { check("wrong") }
    expect(user.reload.customer_id).to eq(other_customer.id)
    expect(user.failed_attempts).to eq(4)
  end

  it "does not recreate a deleted account" do
    rollback(after_rollback: -> { user.reload.destroy! }) { check("wrong") }
    expect(Authentication::User.exists?(user.id)).to be(false)
  end

  it "handles deletion between the tenant lookup and the replay row lock" do
    replaying = false
    allow(Authentication::User).to receive(:find_by).and_wrap_original do |original, **attributes|
      account = original.call(**attributes)
      Authentication::User.find(account.id).destroy! if replaying && account
      account
    end
    rollback(after_rollback: -> { replaying = true }) { check("wrong") }
    expect(Authentication::User.exists?(user.id)).to be(false)
  end

  it "rejects a foreign tenant before recording any effect" do
    rollback { expect(check("wrong", customer_id: other_customer.id)).to be_nil }
    expect(user.reload.failed_attempts).to eq(0)
  end

  it "rejects a matching foreign user/ctx pair inside another tenant's execution boundary" do
    foreign_user = create(:user, customer: other_customer)
    rollback do
      expect(FlowchartRuntime::Authentication.password(
        user: foreign_user, password: "wrong", customer_id: other_customer.id
      )).to be_nil
    end
    expect(foreign_user.reload.failed_attempts).to eq(0)
  end

  it "rechecks a tenant move between lookup and lock acquisition" do
    replaying = false
    allow(Authentication::User).to receive(:find_by).and_wrap_original do |original, **attributes|
      account = original.call(**attributes)
      Authentication::User.find(account.id).update!(customer_id: other_customer.id) if replaying && account
      account
    end
    rollback(after_rollback: -> { replaying = true }) { check("wrong") }
    expect(user.reload.customer_id).to eq(other_customer.id)
    expect(user.failed_attempts).to eq(0)
  end

  it "never restores rolled-back business attributes on the user during security replay" do
    rollback do
      user.update!(first_name: "Business change")
      check("wrong")
    end
    expect(user.reload.first_name).to eq("Test")
    expect(user.failed_attempts).to eq(1)
  end

  it "replays on exception rollback and clears the execution scope" do
    expect {
      described_class.transaction(customer_id: customer.id) do
        check("wrong")
        raise "business failure"
      end
    }.to raise_error("business failure")
    expect(user.reload.failed_attempts).to eq(1)
    expect(described_class::Scope.journal).to be_nil
  end

  [false, true].each do |nested|
    it "serializes competing effects and sends one unlock notification with nested=#{nested}" do
      allow(Authentication::User).to receive(:maximum_attempts).and_return(2)
      allow(Authentication::User).to receive(:unlock_strategy).and_return(:both)
      delivery = instance_double(ActionMailer::MessageDelivery, deliver_later: true)
      expect(Devise.mailer).to receive(:unlock_instructions).once.and_return(delivery)
      barrier = Concurrent::CyclicBarrier.new(4)
      results = Queue.new
      principal = user
      tenant_id = customer.id
      threads = 3.times.map do |index|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            raise "barrier timed out" unless barrier.wait(5)

            attempt = -> { results << FlowchartRuntime::Authentication.password(user: principal, password: "wrong", customer_id: tenant_id) }
            if nested
              nested_transactions([index.even? ? :commit : :rollback, :rollback, :rollback], &attempt)
            else
              described_class.transaction(customer_id: tenant_id) do
                attempt.call
                raise ActiveRecord::Rollback
              end
            end
          end
        rescue StandardError => e
          results << e
        ensure
          described_class::Scope.reset
        end
      end
      raise "barrier timed out" unless barrier.wait(5)

      threads.each(&:join)
      expect(Array.new(results.size) { results.pop }).to eq([nil, nil, nil])
      expect(user.reload.failed_attempts).to eq(3)
      expect(user).to be_access_locked
    end
  end
end
