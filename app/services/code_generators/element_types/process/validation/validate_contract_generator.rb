# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Validation
        class ValidateContractGenerator < BaseGenerator
          generator_metadata do
            description "Runs Reform#validate on ctx[:contract] with ctx[:params] (the page's permitted " \
                        "submitted values) and stores the boolean on validVar (default contract_valid). " \
                        "Invalid fields stay on the contract so the submitter sees Errors.collect " \
                        "(full_messages). onInvalid fail (default) takes the failure track when validate " \
                        "is false; continue returns success so a Decision can branch on validVar — do " \
                        "not save_model on that invalid path. Fails with contract_missing when " \
                        "ctx[:contract] is absent. Call after build_contract; this does not persist."
            category :validation
            version "2.2.0"
            presentation icon: "M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z",
                        color: "emerald",
                        single_use: true,
                        privileged: false
          end

          config_schema do
            enum :onInvalid, %w[fail continue], default: "fail",
                 description: "When Reform#validate returns false: fail (default) takes the failure " \
                              "track so the submitter sees the contract errors; continue returns success " \
                              "so a later Decision can branch on validVar. Never save_model after continue " \
                              "on the invalid path."
            output :validVar, default: "contract_valid",
                   description: "Boolean variable set to the Reform#validate result. Default " \
                                "contract_valid. Branch a Decision on this when onInvalid is continue."
          end

          def generate_body
            lines = [
              fail_with(:contract_missing, unless: "ctx[:contract]"),
              assign(:validVar, "ctx[:contract].validate(ctx[:params] || {})")
            ]
            lines << "true" if value(:onInvalid) == "continue"
            body(*lines)
          end

          def dependencies
            [:build_contract]
          end
        end
      end
    end
  end
end
