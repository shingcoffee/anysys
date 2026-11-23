# frozen_string_literal: true

require "digest"

module Authentication
  # Preserve Devise security effects when a public activity rolls back its
  # business transaction. The journal contains comparison outcomes, never the
  # supplied password or a dirty model snapshot. Effects run in graph order.
  #
  # A commit keeps the original writes. Rolled-back effects wait for every open
  # ancestor to finish before replaying through Devise in a new transaction.
  # Replaying inside a surviving parent would make security writes rollbackable
  # again, even if with_lock used a requires_new savepoint.
  class PasswordEffects
    class Scope < ActiveSupport::CurrentAttributes
      attribute :journal
    end

    Attempt = Data.define(:user_id, :customer_id, :credential_version, :matches)

    # Apply only to the clean instances used for security checks, not the global
    # User class. Devise still generates/persists its token and owns delivery;
    # Rails discards this notification callback if that transaction rolls back.
    module CommittedNotifications
      private

      def send_devise_notification(notification, *args)
        ActiveRecord.after_all_transactions_commit { super(notification, *args) }
      end
    end

    def self.transaction(customer_id:)
      ActiveRecord::Base.transaction do |transaction|
        journal = new(customer_id: customer_id)
        transaction.after_rollback { Scope.set(journal: nil) { journal.replay! } }
        transaction.after_commit { journal.clear }
        Scope.set(journal: journal) { yield }
      end
    end

    def initialize(customer_id:)
      @customer_id = customer_id.to_s
      @attempts = []
    end

    def inspect = "#<#{self.class.name}>"

    def verify(user:, password:, customer_id:)
      return unless customer_id.present? && customer_id.to_s == @customer_id

      with_account(user.id, customer_id) do |account|
        version = credential_version(account)
        PasswordVerification.authenticate(user: account, password: password) do |matches|
          @attempts << Attempt.new(user_id: account.id, customer_id: account.customer_id,
                                   credential_version: version, matches: matches)
        end
      end
    end

    def replay!
      return if @attempts.empty?

      # Rails has popped the completed transaction before invoking callbacks.
      # Resolve the CURRENT parent each time; never register on the finalized
      # transaction whose callback brought us here. Commit callbacks migrate up
      # automatically, whereas each ancestor rollback needs a fresh handoff.
      parent = ActiveRecord::Base.current_transaction
      if parent.open?
        parent.after_commit { replay! }
        parent.after_rollback { replay! }
        return
      end

      persist_attempt(@attempts.first) until @attempts.empty?
    end

    def clear
      @attempts.clear
    end

    private

    def persist_attempt(attempt)
      User.transaction do |transaction|
        # Consume only after durable commit, before notification callbacks. A
        # write failure retains this attempt; a later mail failure must not make
        # a retry count an already-committed attempt a second time.
        transaction.after_commit { @attempts.shift }
        with_account(attempt.user_id, attempt.customer_id) do |account|
          # A concurrent password change, account deletion or tenant move makes
          # the old comparison inapplicable. Never reset/lock a different account
          # version, nor copy the rolled-back counter over concurrent increments.
          next unless credential_version(account) == attempt.credential_version

          verified = account.valid_for_authentication? { attempt.matches }
          PasswordVerification.complete(user: account, verified: verified)
        end
      end
    end

    def with_account(id, customer_id)
      account = User.find_by(id: id, customer_id: customer_id)
      return unless account

      account.with_lock do
        # with_lock reloads after taking the lock; recheck a concurrent move.
        next unless account.customer_id.to_s == @customer_id

        account.extend(CommittedNotifications)
        yield account
      end
    rescue ActiveRecord::RecordNotFound
      # The account may disappear between find_by and with_lock's reload.
      nil
    end

    def credential_version(account)
      Digest::SHA256.hexdigest(account.encrypted_password).freeze
    end
  end
end
