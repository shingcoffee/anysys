# frozen_string_literal: true

module Entries
  # The one way an entity entry is written. Each surface validates its own
  # contract (audience, writable fields) and runs its business logic first —
  # for a page submission that is the page's flowchart — then calls this to
  # sync and persist. +field_errors+ are FlowchartRuntime::Errors::Field values.
  #
  # +audience+ is who is behind the write (admin, member, public, or system
  # when no person is); a status change the entity's lifecycle does not let
  # that audience make is refused on its field (Entities::Lifecycle).
  class Save
    Result = Data.define(:entry, :errors, :field_errors) do
      def ok? = errors.empty?
    end

    # Stands in for a contract when the record was already changed in place.
    Written = Data.define(:model) do
      def sync = nil
    end

    def self.call(...) = new(...).call

    def initialize(contract:, audience:)
      @contract = contract
      @audience = Entities::Lifecycle.audience!(audience)
      @errors = []
      @field_errors = []
    end

    def call
      entry = @contract.model
      EntityEntry.transaction(requires_new: true) do
        @contract.sync
        raise ActiveRecord::Rollback unless lifecycle_allows?(entry) && persist(entry)
      end
      result(@errors.empty? && entry.persisted? ? entry : nil)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved
      record_errors(entry)
      result(nil)
    end

    private

    def result(entry)
      Result.new(entry: entry, errors: @errors, field_errors: @field_errors)
    end

    def lifecycle_allows?(entry)
      violations = Entities::Lifecycle.violations(entry, audience: @audience)
      return true if violations.empty?

      violations.each { |violation| entry.errors.add(violation.slug.to_sym, violation.message) }
      record_errors(entry)
      false
    end

    def persist(entry)
      return true if entry.save

      record_errors(entry)
      false
    end

    def record_errors(entry)
      @errors = entry.errors.full_messages.presence || [I18n.t("common.errors.dynamic.activity_execution_failed")]
      @field_errors = FlowchartRuntime::Errors.of(entry.errors)
    end
  end
end
