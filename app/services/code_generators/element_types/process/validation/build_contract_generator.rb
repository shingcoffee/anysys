# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Validation
        class BuildContractGenerator < BaseGenerator
          CLASS_NAME_FORMAT = /\A[A-Z][A-Za-z0-9_]*(::[A-Z][A-Za-z0-9_]*)*\z/
          # Quoted so GeneratorConformance.dead_ui_fields sees the declared keys.
          CONTRACT_CLASS_FIELD = "contractClass"
          MODEL_VARIABLE_FIELD = "modelVariable"

          generator_metadata do
            description "Wraps a loaded EntityEntry (modelVariable, default model) in a Reform form and " \
                        "stores it as ctx[:contract]. Uses EntityEntryContract.build_for(bound_entity, " \
                        "audience, writable_slugs) unless contractClass names another Reform class that " \
                        "implements the same build_for factory. Does not validate or save. Follow with " \
                        "validate_contract then save_model. Fails with record_missing when the model " \
                        "variable is empty. Use this once per record you will validate; after save_model, " \
                        "set system-filled fields with update_model assignments instead of rebuilding."
            category :validation
            version "2.1.0"
            presentation icon: "M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z",
                        color: "indigo",
                        single_use: true,
                        privileged: false
          end

          config_schema do
            literal :contractClass, default: "EntityEntryContract", placeholder: true,
                    description: "Reform class used to wrap the record. Default EntityEntryContract, " \
                                 "which builds an audience-scoped form from the bound entity schema. " \
                                 "Must be a constant path such as EntityEntryContract or Shop::OrderContract."
            input :modelVariable, default: "model",
                  description: "Context path of the EntityEntry the form wraps. Default model (the page " \
                               "record seeded on submit). Use a loaded variable such as cart only when " \
                               "that row is the same bound entity."

            validate do |cfg, errors|
              name = cfg[CONTRACT_CLASS_FIELD].presence || cfg[CONTRACT_CLASS_FIELD.to_sym].presence || "EntityEntryContract"
              errors.add(:contractClass, :invalid_class_name) unless CLASS_NAME_FORMAT.match?(name.to_s)
            end
          end

          def generate_body
            klass = value(:contractClass).to_s
            raise_unsafe_value!(:contractClass) unless CLASS_NAME_FORMAT.match?(klass)

            body(
              <<~RUBY.chomp,
                unless #{read(:modelVariable)}
                  return FlowchartRuntime::Step.fail(ctx, :record_missing, field: :modelVariable)
                end
              RUBY
              "form = #{klass}.build_for(ctx[:bound_entity], audience: ctx[:audience], " \
              "writable_slugs: ctx[:writable_slugs])",
              "ctx[:contract] = form.new(#{read(:modelVariable)})",
              "true"
            )
          end

          def dependencies
            [:new_model]
          end
        end
      end
    end
  end
end
