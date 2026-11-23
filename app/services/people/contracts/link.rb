# frozen_string_literal: true

require "reform/form"

module People
  module Contracts
    class Link < Reform::Form
      property :user_id, virtual: true

      validate :entity_is_person
      validate :user_is_available
      validate :entry_is_unlinked
      validate :user_is_unlinked

      private

      def entity_is_person
        return if model.entity&.person?

        errors.add(:base, I18n.t("people.errors.not_a_person"))
      end

      # Missing, other-tenant, and inactive share one message so a cross-tenant
      # id never confirms that a user exists.
      def user_is_available
        return if linkable_user

        errors.add(:base, I18n.t("people.errors.user_unavailable"))
      end

      def entry_is_unlinked
        return unless model.linked?

        errors.add(:base, I18n.t("people.errors.already_linked"))
      end

      def user_is_unlinked
        return unless linkable_user
        return unless EntityEntry.where(entity_id: model.entity_id, user_id: linkable_user.id)
                                 .where.not(id: model.id).exists?

        errors.add(:base, I18n.t("people.errors.user_already_linked"))
      end

      def linkable_user
        return @linkable_user if defined?(@linkable_user)

        id = user_id.presence
        @linkable_user = id && Authentication::User.find_by(
          id: id,
          customer_id: model.customer_id,
          status: :active
        )
      end
    end
  end
end
