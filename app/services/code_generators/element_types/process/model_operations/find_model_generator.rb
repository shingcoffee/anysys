# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module ModelOperations
        class FindModelGenerator < BaseGenerator
          generator_metadata do
            description "Loads one bound-entity row into resultVar (default model) by id (idSource), by " \
                        "one attribute (findField and findValue), or as the signed-in member's person " \
                        "record (current_person, from ctx[:current_person_ids], never params). Optionally " \
                        "sets foundVar to whether a row existed, and lock takes a FOR UPDATE lock for a " \
                        "later write in this submit. onNotFound fail (default) refuses with " \
                        "record_not_found or notFoundMessage; nil leaves the variable empty and continues; " \
                        "new builds an unsaved tenant row. Use related_record or referenced_record for " \
                        "another entity, upsert_model to find-or-create, and load_current_user for the User."
            category :model_operations
            version "5.3.0"
            presentation icon: "M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z", color: "cyan",
              single_use: true, privileged: false
          end

          config_schema do
            enum :findBy, %w[id attribute current_person], default: "id",
                 description: "How to look the row up. id uses idSource (default params.id). attribute " \
                              "matches findField to findValue. current_person loads the signed-in " \
                              "member's linked person entry and ignores posted ids."
            input :idSource, default: "params.id", visible: { findBy: "id" },
                  description: "Context path of the id to look up when findBy is id. Default params.id " \
                               "(the page record's id on update). Example: params.order_id."
            entity_attribute :findField, of: :bound, example: "email", visible: { findBy: "attribute" },
                             description: "Bound-entity attribute slug to match when findBy is attribute. " \
                                          "Example: email. Combined with findValue as an equality lookup."
            input :findValue, example: "params.email", visible: { findBy: "attribute" },
                  description: "Context path of the value to match when findBy is attribute. Example: " \
                               "params.email. Compared with equality against findField."
            enum :onNotFound, %w[fail nil new], default: "fail",
                 description: "When no row matches: fail refuses the submit with record_not_found (or " \
                              "notFoundMessage); nil stores nothing and continues so a Decision can " \
                              "branch on foundVar; new builds an unsaved tenant-scoped row (and copies " \
                              "the lookup attribute when findBy is attribute)."
            localized_text :notFoundMessage, group: :advanced, visible: { onNotFound: "fail" },
                           description: "Optional localized submitter message used instead of the default " \
                                        "record_not_found text when onNotFound is fail. Requires an en value."
            output :resultVar, default: "model",
                   description: "Context variable that receives the loaded row, or the new unsaved row " \
                                "when onNotFound is new. Default model."
            output :foundVar, group: :advanced,
                   description: "Optional boolean variable set before onNotFound runs: true when a " \
                                "matching row existed, false when it did not. Leave blank to skip."
            flag :lock, default: false, group: :advanced,
                 description: "When true, the lookup uses SELECT FOR UPDATE so a later update_model or " \
                              "adjust_number in this submit sees a consistent row. Default false. Only " \
                              "holds for the page-submit transaction."
            requires :findField, when: { findBy: "attribute" }
            requires :findValue, when: { findBy: "attribute" }
          end

          def generate_body
            result = value(:resultVar)
            lines = [assign(:resultVar, lookup_call)]
            lines << assign(:foundVar, "!ctx[:#{result}].nil?") if value(:foundVar).present?
            lines.concat(not_found_lines(result, missing_field))
            body(*lines)
          end

          private

          def lookup_call
            case value(:findBy)
            when "current_person"
              value(:lock) ? "FlowchartRuntime::Entries.find_current_person(ctx, lock: true)" : "FlowchartRuntime::Entries.find_current_person(ctx)"
            when "attribute"
              pair = "#{read(:findField)} => #{read(:findValue)}"
              if value(:lock)
                %(FlowchartRuntime::Entries.find_by(ctx, { #{pair} }, true))
              else
                %(FlowchartRuntime::Entries.find_by(ctx, #{pair}))
              end
            else
              pair = %{"id" => #{read(:idSource)}}
              if value(:lock)
                %(FlowchartRuntime::Entries.find_by(ctx, { #{pair} }, true))
              else
                %(FlowchartRuntime::Entries.find_by(ctx, #{pair}))
              end
            end
          end

          def missing_field
            case value(:findBy)
            when "current_person" then nil
            when "attribute" then :findValue
            else :idSource
            end
          end

          def not_found_lines(result, missing_field)
            case value(:onNotFound)
            when "nil"
              ["true"]
            when "new"
              build_new = "ctx[:#{result}] = FlowchartRuntime::Entries.scope(ctx).new(customer_id: ctx[:customer_id])"
              assign_lookup =
                if value(:findBy) == "attribute"
                  "  FlowchartRuntime::Entries.assign(ctx[:#{result}], { #{read(:findField)} => #{read(:findValue)} }, strict: true)"
                end
              ["if ctx[:#{result}].nil?", "  #{build_new}", assign_lookup, "end", "true"].compact
            else
              [not_found_failure(result, missing_field), "true"]
            end
          end

          def not_found_failure(result, missing_field)
            message = value(:notFoundMessage)
            english = message.is_a?(Hash) ? (message["en"] || message[:en]).to_s.strip : ""
            unless english.empty?
              args = ["ctx", read(:notFoundMessage), "code: :record_not_found"]
              args << "field: :#{missing_field}" if missing_field
              return "return FlowchartRuntime::Step.fail_message(#{args.join(', ')}) unless ctx[:#{result}]"
            end

            fail_with(:record_not_found, field: missing_field, unless: "ctx[:#{result}]")
          end
        end
      end
    end
  end
end
