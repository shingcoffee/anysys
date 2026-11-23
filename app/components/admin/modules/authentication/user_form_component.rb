# frozen_string_literal: true

module Admin
  module Modules
    module Authentication
      # Create and edit form for a tenant user. Section cards match the user
      # detail page: tinted header, then the fields for that part of the account.
      # As a journey's user step (+journey+) the password is generated on save,
      # so the form asks for none and posts the journey's key.
      class UserFormComponent < ApplicationComponent
        include EntityAttributeGroupingHelper

        LOCK_ICON = "M7 11V7a5 5 0 0110 0v4M6 11h12a2 2 0 012 2v6a2 2 0 01-2 2H6a2 2 0 01-2-2v-6a2 2 0 012-2z"

        attr_reader :user, :url, :method, :journey

        def initialize(user:, url:, method:, journey: nil)
          @user = user
          @url = url
          @method = method
          @journey = journey
        end

        def password_description
          if journey then t("admin_modules.users.form.generated_password_hint")
          elsif user.persisted? then t("admin_modules.users.form.password_hint")
          end
        end

        def cancel_path
          if user.persisted?
            helpers.admin_modules_authentication_user_path(helpers.current_customer_id, user)
          else
            helpers.admin_modules_authentication_users_path(helpers.current_customer_id)
          end
        end

        def selected_role
          helpers.params.dig(:authentication_user, :role).presence || user.primary_role_key
        end

        def role_options
          %w[owner admin member].map { |key| [t("admin_modules.users.roles.#{key}"), key] }
        end

        def password_placeholder
          key = user.persisted? ? "password_placeholder_edit" : "password_placeholder_new"
          t("admin_modules.users.form.#{key}")
        end

        def submit_label
          return t("admin_modules.users.actions.update_user") if user.persisted?

          journey ? t("admin_modules.users.actions.create_user_and_continue") : t("admin_modules.users.actions.create_user")
        end

        def tile(color)
          "#{attribute_group_color_classes(color)} text-white"
        end

        def label_class(required:)
          required ? "form-label form-label-required" : "form-label"
        end
      end
    end
  end
end
