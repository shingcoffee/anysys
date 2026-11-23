# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Authentication
        class GrantsEditorComponent < ViewComponent::Base
          ALL_ACTIONS = %i[read create update destroy manage].freeze

          def initialize(role:, catalog:, granted_keys:, customer:)
            @role         = role
            @catalog      = catalog
            @granted_keys = granted_keys
            @customer     = customer
          end

          attr_reader :role, :catalog, :granted_keys, :customer

          def locked? = role.locked_grants?

          def owner_access? = role.key == "owner"

          def display_label(descriptor)
            return descriptor.label unless descriptor.subject_type == "Route"

            GrantRouteLabel.new(descriptor.subject_key).label
          end

          def group_display_label(group)
            return group[:label] unless group[:key].start_with?("admin")

            GrantRouteLabel.new("#{group[:key].tr('.', '/')}/resource").context
          end

          def total_actions
            catalog.groups.sum { |g| g[:descriptors].sum { |d| d.actions.size } }
          end

          def total_granted
            catalog.groups.sum { |g| group_granted_count(g) }
          end

          def group_total(group)
            group[:descriptors].sum { |d| d.actions.size }
          end

          def group_granted_count(group)
            group[:descriptors].sum do |d|
              d.actions.count { |a| granted?(d, a) }
            end
          end

          def granted?(descriptor, action)
            owner_access? || granted_keys.include?(grant_key(descriptor, action))
          end

          def grant_key(descriptor, action)
            "#{descriptor.subject_type}:#{descriptor.subject_key}:#{descriptor.subject_id}:#{action}"
          end

          def all_actions_present
            ALL_ACTIONS
          end

          def update_url
            helpers.admin_settings_modules_authentication_role_grants_path(customer.id, role)
          end
        end
      end
    end
  end
end
