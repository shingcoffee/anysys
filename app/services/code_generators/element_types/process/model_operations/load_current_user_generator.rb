# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class LoadCurrentUserGenerator < BaseGenerator
          generator_metadata do
            description "Loads the signed-in user for this customer as a frozen read-only hash. Use this to branch on role or to address a notification; do not treat id as a person or record id (that mapping is person_entries). Writes resultVar (default current_user) to a hash with string keys id, email, name, role, and person_entries (person entity id to that user's own record id). When required is true (default), fails as load_current_user.not_signed_in if no signed-in user belongs to this tenant. When required is false, stores nil and the step still succeeds."
            category :model_operations
            version "1.1.0"
            presentation icon: "M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z",
              color: "cyan", single_use: true, privileged: false
          end

          config_schema do
            output :resultVar, default: "current_user",
                   description: "Ctx variable that receives the frozen user hash. Read keys with ctx[:current_user][\"email\"], [\"name\"], [\"role\"], [\"id\"], or [\"person_entries\"]."
            flag :required, default: true,
                 description: "When true (default), the step fails as load_current_user.not_signed_in if ctx[:current_user_id] is missing or the user is not in this tenant. When false, resultVar is nil and the step succeeds."
          end

          def generate_body
            load = "FlowchartRuntime::CurrentUser.load(ctx)"
            unless value(:required)
              return body(
                assign(:resultVar, load),
                "true"
              )
            end

            body(
              "user = #{load}",
              assign(:resultVar, "user"),
              fail_with('"load_current_user.not_signed_in"', unless: "user"),
              "true"
            )
          end
        end
      end
    end
  end
end
