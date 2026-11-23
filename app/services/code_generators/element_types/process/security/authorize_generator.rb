# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Security
        class AuthorizeGenerator < BaseGenerator
          AUTH_TYPES = FlowchartRuntime::Authorization::AUTH_TYPES
          ON_DENIED = %w[fail flag].freeze
          RESERVED_ROLES = FlowchartRuntime::Authorization::RESERVED_ROLES
          ABILITY_ACTION_RE = FlowchartRuntime::Authorization::ABILITY_ACTION_RE

          generator_metadata do
            description "Allows the step to continue only when the actor has a reserved role, a CanCanCan " \
                        "ability, any listed reserved role, or owns the record (user_id). Reads userExpression " \
                        "(default current_user). Use authenticate first to prove identity. Roles are only " \
                        "owner, admin, and member; record_owner is the member-owns-this-row check. " \
                        "Denied writes authorize.denied unless onDenied is flag (then resultVar is boolean)."
            category :security
            version "3.0.0"
            presentation icon: "M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z",
                          color: "red", single_use: false, privileged: false
          end

          config_schema do
            enum :authType, AUTH_TYPES, default: "role_check",
                 description: "How this step decides. role_check: user must have roleName. multi_role: user must " \
                              "have any role in roleList (owner/admin/member). ability_check: CanCanCan " \
                              "can?(abilityAction, abilityResource) plus tenant match. record_owner: the record's " \
                              "user_id must equal the user's id in this tenant."
            input :userExpression, default: "current_user",
                  description: "Context path of the Authentication::User. Default current_user (written by Load " \
                               "current user). Falls back to the Warden session when the value is not a User."
            enum :roleName, RESERVED_ROLES, default: "admin", visible: { authType: "role_check" },
                 description: "Reserved role required for role_check. owner, admin, or member only. Default admin. " \
                              "A user has exactly one reserved role."
            literal :abilityAction, example: "read", visible: { authType: "ability_check" },
                    description: "CanCanCan action name, e.g. read or update. Letters, digits, and underscores only. " \
                                 "Required for ability_check."
            input :abilityResource, example: "record", visible: { authType: "ability_check" },
                  description: "Context path of the subject passed to CanCanCan, e.g. record. Another tenant's " \
                               "row is denied even for an admin. Required for ability_check."
            input :recordVariable, example: "model", visible: { authType: "record_owner" },
                  description: "Context path of the EntityEntry (or hash with user_id) the member must own, " \
                               "e.g. model. Admin/owner do not auto-pass; use role_check for staff."
            list :roleList, item: :literal, example: %w[admin], visible: { authType: "multi_role" },
                 description: "Reserved roles; the user may hold any one of them. Values must be owner, admin, " \
                              "or member. Example: admin, member. Required for multi_role."
            enum :onDenied, ON_DENIED, default: "fail",
                 description: "fail: stop with authorize.denied or deniedMessage. flag: write resultVar true/false " \
                              "and continue so a later decision can branch."
            output :resultVar, default: "authorized", visible: { onDenied: "flag" },
                   description: "Ctx key set to true or false when onDenied is flag. Example: authorized."
            localized_text :deniedMessage, group: :advanced, visible: { onDenied: "fail" },
                           description: "Optional localized hash {en, zh-CN} shown instead of authorize.denied " \
                                        "when onDenied is fail. Leave blank to use the default translation."
            requires :abilityAction, when: { authType: "ability_check" }
            requires :abilityResource, when: { authType: "ability_check" }
            requires :recordVariable, when: { authType: "record_owner" }
            requires :roleList, when: { authType: "multi_role" }
            validate do |cfg, errors|
              next unless cfg["authType"].to_s == "ability_check"

              action = cfg["abilityAction"].to_s
              next if action.blank? || action.match?(ABILITY_ACTION_RE)

              errors.add(:abilityAction, :invalid_ability_action, action: action)
            end
            validate do |cfg, errors|
              next unless cfg["authType"].to_s == "multi_role"

              roles = Array(cfg["roleList"]).map(&:to_s).reject(&:blank?)
              bad = roles - RESERVED_ROLES
              errors.add(:roleList, :invalid_role_list, entries: bad.join(", ")) if bad.any?
            end
          end

          def generate_body
            if value(:onDenied).to_s == "flag"
              body(assign(:resultVar, allowed_call), "true")
            else
              body(
                "allowed = #{allowed_call}",
                "unless allowed",
                "  #{denial_return}",
                "end",
                "true"
              )
            end
          end

          private

          def allowed_call
            "FlowchartRuntime::Authorization.allowed?(ctx, #{auth_args})"
          end

          def auth_args
            parts = ["user: #{read(:userExpression)}", "type: #{read(:authType)}"]
            case value(:authType).to_s
            when "ability_check"
              action = ability_action
              parts << "action: #{action.inspect}" unless action == "read"
              resource = value(:abilityResource).to_s.strip
              parts << "resource: #{read(:abilityResource)}" unless resource.empty?
            when "multi_role"
              parts << "roles: #{role_list_literal}"
            when "record_owner"
              record = value(:recordVariable).to_s.strip
              parts << "resource: #{read(:recordVariable)}" unless record.empty?
            else
              role = value(:roleName).to_s
              parts << "role: #{read(:roleName)}" unless role.empty? || role == "admin"
            end
            parts.join(", ")
          end

          def role_list_literal
            raw = Array(value(:roleList)).map(&:to_s).select { |role| RESERVED_ROLES.include?(role) }
            "[#{raw.map { |role| ":#{role}" }.join(', ')}]"
          end

          def ability_action
            action = value(:abilityAction).to_s
            action.match?(ABILITY_ACTION_RE) ? action : "read"
          end

          def denial_return
            if denied_message?
              "return FlowchartRuntime::Step.fail_message(ctx, #{read(:deniedMessage)})"
            else
              fail_with('"authorize.denied"')
            end
          end

          def denied_message?
            raw = value(:deniedMessage)
            return false unless raw.is_a?(Hash)

            english = raw["en"] || raw[:en]
            english.to_s.strip.present?
          end
        end
      end
    end
  end
end
