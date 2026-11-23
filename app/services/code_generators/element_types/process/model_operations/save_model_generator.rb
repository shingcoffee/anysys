# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class SaveModelGenerator < BaseGenerator
          generator_metadata do
            description "Persists ctx[:contract] through Entries::Save after Reform#sync: the canonical " \
                        "page-submit write after build_contract and validate_contract. Writes " \
                        "ctx[:contract].model (the wrapped EntityEntry), including the page record's " \
                        "bridge rows on first save. onInvalid fail (default) follows a false save onto " \
                        "the failure track so the submitter sees contract and save errors; continue keeps " \
                        "going so a Decision can branch on savedVar. Fails with contract_missing when " \
                        "ctx[:contract] is absent. Use update_model with valuesFrom assignments to set " \
                        "system-filled fields after this save."
            category :model_operations
            version "5.2.0"
            presentation icon: "M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3 3m0 0l-3-3m3 3V4",
              color: "green", single_use: true, privileged: false
          end

          config_schema do
            enum :onInvalid, %w[fail continue], default: "fail",
                 description: "When Entries::Save returns false: fail (default) takes the failure track; " \
                              "continue returns success so a later Decision can branch on savedVar. " \
                              "Does not skip Reform validation — run validate_contract first."
            output :savedVar, group: :advanced,
                   description: "Optional boolean variable set to whether Entries::Save succeeded. Leave " \
                                "blank to skip. Useful when onInvalid is continue."
          end

          def generate_body
            continue_on_invalid = value(:onInvalid) == "continue"
            saved = value(:savedVar)
            inner =
              if saved.present?
                [
                  "saved = FlowchartRuntime::Entries.save(ctx, ctx[:contract])",
                  assign(:savedVar, "saved"),
                  continue_on_invalid ? "saved || true" : "saved"
                ]
              elsif continue_on_invalid
                ["FlowchartRuntime::Entries.save(ctx, ctx[:contract]) || true"]
              else
                ["FlowchartRuntime::Entries.save(ctx, ctx[:contract])"]
              end
            body(
              fail_with(:contract_missing, unless: "ctx[:contract]"),
              attempt('"save_model.failed"', FlowchartRuntime::Entries::Error) { inner }
            )
          end

          def dependencies
            [:validate_contract]
          end
        end
      end
    end
  end
end
