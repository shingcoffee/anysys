# frozen_string_literal: true

module FlowchartRuntime
  # Tenant-scoped snapshot of the signed-in user for generated activities.
  # Returns a frozen Hash so Authorization keeps treating it as no principal.
  module CurrentUser
    class Error < StandardError; end

    FIELDS = %w[id email name role person_entries].freeze

    module_function

    def load(ctx)
      customer_id = ctx && ctx[:customer_id]
      user_id = ctx && ctx[:current_user_id]
      return nil if customer_id.blank? || user_id.blank?

      user = ::Authentication::User.find_by(id: user_id, customer_id: customer_id)
      return nil unless user

      {
        "id" => user.id,
        "email" => user.email,
        "name" => user.display_name,
        "role" => user.primary_role_key,
        "person_entries" => People::Ownership.person_entry_ids(user).freeze
      }.freeze
    end
  end
end
