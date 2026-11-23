# frozen_string_literal: true

module Roles
  module Operation
    class Update
      Result = Roles::Operation::Create::Result

      def self.call(role:, params:)
        return Result.new(success?: false, model: role, errors: { base: [I18n.t("auth.errors.system_role_uneditable")] }) if role.system?

        form = Roles::Contract::Update.new(role)
        if form.validate(params)
          form.save
          Result.new(success?: true, model: role, errors: nil)
        else
          Result.new(success?: false, model: role, errors: form.errors)
        end
      end
    end
  end
end
