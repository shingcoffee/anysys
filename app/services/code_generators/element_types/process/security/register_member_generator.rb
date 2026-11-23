# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Security
        class RegisterMemberGenerator < BaseGenerator
          generator_metadata do
            description "Registers a public visitor as a passwordless member on a person entity and writes " \
                        "{status: created|existing} to resultVar. Reads personVar (the EntityEntry) and " \
                        "identityVar (first_name, last_name, email). Taken emails and quota exhaustion look " \
                        "like existing (anti-enumeration). Use authenticate for sign-in, not this step. " \
                        "Fails public_only, person_entity_required, signup_disabled, or unavailable."
            category :security
            version "1.2.0"
            presentation icon: "M18 9v3m0 0v3m0-3h3m-3 0h-3m-2-5a4 4 0 11-8 0 4 4 0 018 0zM3 20a6 6 0 0112 0v1H3v-1z",
                          color: "red", single_use: true, privileged: false
          end

          config_schema do
            input :personVar, default: "model",
                  description: "Context path of the person EntityEntry this step writes, e.g. model. " \
                               "Must belong to ctx[:customer_id] and the bound person entity."
            input :identityVar, default: "identity",
                  description: "Context path of the identity hash with first_name, last_name, and email, " \
                               "e.g. identity. A taken email still succeeds as status existing."
            output :resultVar, default: "registration",
                   description: "Ctx key that receives {status: created} or {status: existing}. Default " \
                                "registration. Browser-visible success is the same for both."
          end

          def generate_body
            body(
              assign(:resultVar,
                     "FlowchartRuntime::Registration.call(ctx, person: #{read(:personVar)}, identity: #{read(:identityVar)})")
            )
          end
        end
      end
    end
  end
end
