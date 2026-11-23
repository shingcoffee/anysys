# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Workflow
        class SelectAssigneeGenerator < BaseGenerator
          STRATEGIES = FlowchartRuntime::Assignment::STRATEGIES
          RETURNS = %w[candidate id].freeze
          ON_EMPTY = %w[fail nil].freeze
          CANDIDATE_SOURCES = FlowchartRuntime::Assignment::SOURCES
          ROLES = FlowchartRuntime::Assignment::ROLES

          generator_metadata do
            description "Picks one owner or agent from a candidate pool for ticket routing and lead distribution. Load candidates yourself into sourceVariable (query_models of a staff entity, or a prior list), or set candidateSource to role to pick among this tenant's active admin or member users. Strategies: round_robin (tenant-scoped counter), least_loaded, weighted, random, first. Use transition_state to move a status after assignment. Reads sourceVariable or the tenant user list. Writes the chosen candidate or id to resultVar. Refuses select_assignee.no_candidates when the pool is empty and onEmpty is fail."
            category :workflow
            version "1.1.0"
            presentation icon: "M18 9v3m0 0v3m0-3h3m-3 0h-3m-2-5a4 4 0 11-8 0 4 4 0 018 0zM3 20a6 6 0 0112 0v1H3v-1z",
                          color: "sky", single_use: false, privileged: false
          end

          config_schema do
            enum :candidateSource, CANDIDATE_SOURCES, default: "variable",
                 description: "variable (default): pick from the array at sourceVariable. role: pick from this tenant's active users who have the reserved role in role (admin or member). Round-robin still uses poolKey."
            input :sourceVariable, example: "agents", placeholder: true,
                  visible: { candidateSource: "variable" },
                  description: "Ctx path of the candidate array when candidateSource is variable, such as agents. Items may be hashes, EntityEntry records, User records, or scalar ids."
            enum :role, ROLES, default: "admin", visible: { candidateSource: "role" },
                 description: "Reserved role whose active users of this customer form the pool when candidateSource is role. admin is customer administrators; member is self-signed-up members. Never includes owner."
            enum :strategy, STRATEGIES, default: "round_robin",
                 description: "How one candidate is chosen from the eligible pool. round_robin rotates a tenant-scoped counter named by poolKey. least_loaded picks the lowest loadField. weighted draws by weightField. random picks uniformly. first takes the first remaining."
            literal :poolKey, default: "default", visible: { strategy: "round_robin" },
                    description: "Tenant-scoped name of the rotation counter used by round_robin, such as support_desk. Separate keys keep independent rotations (for example billing vs support)."
            literal :weightField, default: "weight", visible: { strategy: "weighted" },
                    description: "Hash or record field that holds each candidate's relative weight when strategy is weighted, such as weight. Missing or non-numeric weights count as 0."
            literal :loadField, default: "open_items", visible: { strategy: "least_loaded" },
                    description: "Hash or record field that holds each candidate's current load when strategy is least_loaded, such as open_items. Missing or non-numeric loads count as 0."
            literal :availabilityField, default: "", group: :advanced,
                    description: "When set, only candidates whose field is truthy (true, 1, \"true\") are eligible, such as available. Leave blank to include everyone."
            input :excludeVariable, default: "", group: :advanced,
                  description: "Optional ctx path of an id or list of ids to skip, such as previous_assignee. Compared as strings against idField. Leave blank to skip nobody."
            literal :idField, default: "id",
                    description: "Hash or record field used as the candidate id, such as id. Scalar candidates use their own value. Used for exclude matching and when returns is id."
            enum :returns, RETURNS, default: "candidate",
                 description: "candidate (default) stores the whole chosen item on resultVar. id stores only the value of idField (or the scalar itself)."
            enum :onEmpty, ON_EMPTY, default: "fail",
                 description: "When no eligible candidate remains: fail refuses the run as select_assignee.no_candidates; nil stores nil on resultVar and continues."
            output :resultVar, default: "assignee",
                   description: "Ctx variable later steps read for the chosen assignee, such as assignee. A whole candidate or an id according to returns."
            requires :sourceVariable, when: { candidateSource: "variable" }
            validate do |_cfg, errors|
              next unless value(:strategy).to_s == "round_robin"

              name = value(:poolKey).to_s.strip
              errors.add(:poolKey, :required) if name.empty?
            end
          end

          def generate_body
            var = value(:resultVar)
            attempt('"select_assignee.failed"', FlowchartRuntime::Assignment::Error) do
              [
                assign(:resultVar, pick_call),
                empty_guard(var),
                "true"
              ]
            end
          end

          private

          def pick_call
            "FlowchartRuntime::Assignment.pick(ctx, #{pool_source}, #{pick_args})"
          end

          def pool_source
            if value(:candidateSource).to_s == "role"
              "FlowchartRuntime::Assignment.users_of_role(ctx, #{read(:role)})"
            else
              read(:sourceVariable)
            end
          end

          def pick_args
            strategy = value(:strategy).to_s
            [
              "strategy: #{read(:strategy)}",
              ("pool_key: #{read(:poolKey)}" if strategy == "round_robin" && value(:poolKey).to_s != "default"),
              ("weight_field: #{read(:weightField)}" if strategy == "weighted" && value(:weightField).to_s != "weight"),
              ("load_field: #{read(:loadField)}" if strategy == "least_loaded" && value(:loadField).to_s != "open_items"),
              ("availability_field: #{read(:availabilityField)}" if value(:availabilityField).to_s.strip.present?),
              ("exclude: #{read(:excludeVariable)}" if value(:excludeVariable).to_s.strip.present?),
              ("id_field: #{read(:idField)}" unless value(:idField).to_s == "id"),
              ("returns: #{read(:returns)}" unless value(:returns).to_s == "candidate")
            ].compact.join(", ")
          end

          def empty_guard(var)
            return unless value(:onEmpty).to_s == "fail"

            %(next FlowchartRuntime::Step.fail(ctx, :"select_assignee.no_candidates") unless ctx[:#{var}])
          end
        end
      end
    end
  end
end
