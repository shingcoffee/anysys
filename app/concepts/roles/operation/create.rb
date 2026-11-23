# frozen_string_literal: true

module Roles
  module Operation
    class Create
      Result = Struct.new(:success?, :model, :errors, keyword_init: true) do
        def [](k) = send(k)
      end

      def self.call(customer:, params:)
        role = Role.new(customer: customer, system: false, locked_grants: false)
        form = Roles::Contract::Create.new(role)
        if form.validate(params) && unique?(customer, params[:key])
          form.save
          Result.new(success?: true, model: role, errors: nil)
        else
          form.errors.add(:key, I18n.t("auth.errors.role_key_taken")) unless unique?(customer, params[:key])
          Result.new(success?: false, model: role, errors: form.errors)
        end
      end

      def self.unique?(customer, key)
        return false if key.blank?
        !customer.roles.exists?(key: key)
      end
    end
  end
end
