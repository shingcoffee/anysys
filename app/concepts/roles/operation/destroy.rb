# frozen_string_literal: true

module Roles
  module Operation
    class Destroy
      Result = Roles::Operation::Create::Result

      def self.call(role:)
        return Result.new(success?: false, model: role, errors: { base: [I18n.t("auth.errors.system_role_undeletable")] }) if role.system?

        role.destroy!
        Result.new(success?: true, model: role, errors: nil)
      end
    end
  end
end
