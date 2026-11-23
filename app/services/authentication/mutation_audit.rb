# frozen_string_literal: true

module Authentication
  # Persist outcome facts with the account mutation, so an enclosing rollback
  # removes both. Explicit projections keep credentials and submitted params out
  # of the ledger; the existing instrumentation logs success only after commit.
  class MutationAudit
    def self.mfa(user:, request: nil, actor: nil, source:)
      CredentialLifecycle.with_current(user) do |account|
        before = mfa_state(account)
        result = yield
        next result if result.respond_to?(:success?) && !result.success?

        after = mfa_state(account.reload)
        event = if !before[:required] && after[:required]
          :mfa_enabled
        elsif before[:configured] && !after[:configured]
          :mfa_disabled
        end
        record(event, user: account, request: request, actor: actor, source: source,
               before: before, after: after) if event
        result
      end
    end

    # Caller holds the account lock and mutation transaction (Assign or the
    # controller's guarded single-join deletion). No-op assignments emit nothing.
    def self.roles(user:, before_role_ids:, request: nil, actor: nil)
      before_ids = before_role_ids.sort.uniq
      after_ids = UsersRole.where(user_id: user.id).pluck(:role_id).sort.uniq
      { role_revoked: before_ids - after_ids, role_granted: after_ids - before_ids }.each do |event, ids|
        next if ids.empty?

        record(event, user: user, request: request, actor: actor, source: "role_assignment",
               before: { role_ids: before_ids }, after: { role_ids: after_ids }, role_ids: ids)
      end
    end

    def self.mfa_state(user)
      { required: user.mfa_required?, configured: user.mfa_configured? }
    end
    private_class_method :mfa_state

    def self.record(event, user:, request:, actor:, source:, before:, after:, **facts)
      AuditLog.record(event: event, user: user, request: request, defer_logging: true,
                      actor_id: actor&.id, source: source, outcome: "success",
                      before: before, after: after, **facts)
    end
    private_class_method :record
  end
end
