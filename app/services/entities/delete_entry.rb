# frozen_string_literal: true

module Entities
  # The one way an entity entry is deleted: a refused destroy (a dependent
  # restriction or foreign key) keeps the row and reports why.
  class DeleteEntry
    Result = Struct.new(:ok, :entry, :errors, keyword_init: true) do
      def success? = ok
    end

    def self.call(entry:)
      entry.class.transaction(requires_new: true) { entry.destroy! }
      Result.new(ok: true, entry: entry, errors: [])
    rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey => error
      entry.reload if entry.persisted?
      errors = error.respond_to?(:record) ? error.record.errors.full_messages : []
      entry.errors.add(:base, :invalid) if errors.empty?
      Result.new(ok: false, entry: entry, errors: errors.presence || entry.errors.full_messages)
    end
  end
end
