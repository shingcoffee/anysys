# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Loop
      class LoopGenerator < BaseGenerator
        include CodeGenerators::Shared::ConditionBuilder

        MAX_LOOP_ITERATIONS = 10_000
        HEADER_LOCALS = %w[state ctx].freeze
        # A loop header is the whole body of its step method, one level in.
        ENTER_WIDTH = CodeGenerators::SourceFormatter::STEP_WIDTH - 2

        generator_metadata do
          description "Repeats the elements of its body, compiled to a header step that routes into the body or " \
                      "out through Done. The header has two outgoing connections: one into the body, whose last " \
                      "element connects back to the loop, and one exit taken when the loop finishes. Loops do not " \
                      "nest, and reaching maxIterations refuses the run instead of looping forever."
          category :flow_control
          version "2.0.2"
        end

        config_schema do
          enum :loopType, %w[while for_each], default: "while", required: true,
                          description: "while repeats as long as condition holds. for_each runs the body once " \
                                       "per item of collection."
          flag :runOnceFirst, default: false, visible: { loopType: "while" },
                              description: "Run the body once before condition is first checked (do-while)."
          conditions :condition, required: true, visible: { loopType: "while" },
                                 description: "Checked before every pass; the loop exits through Done as soon " \
                                              "as it is false."
          input :collection, required: true, example: "items", placeholder: true, visible: { loopType: "for_each" },
                             description: "Path of the list to walk, without the ctx. prefix, such as order_lines " \
                                          "or model.items; a missing value counts as an empty list."
          literal :itemVariable, default: "item", placeholder: true, visible: { loopType: "for_each" },
                                 description: "Variable holding the current item during each pass (ctx[:item])."
          integer :maxIterations, min: 1, max: 10_000, default: 100, placeholder: true,
                                  description: "Safety cap on passes; reaching it refuses the run. Set it above " \
                                               "the largest list or retry count you expect."
          conditions :stopWhen, group: :advanced,
                                description: "Checked at the start of each pass (for_each: once the item is " \
                                             "bound); when true the loop exits early through Done."
          conditions :skipWhen, group: :advanced, visible: { loopType: "for_each" },
                                description: "Items for which this holds are skipped without running the body " \
                                             "and are not collected."
          literal :indexVariable, default: "index", placeholder: true, group: :advanced,
                  visible: { loopType: "for_each" },
                  description: "Variable holding the zero-based position of the current item (ctx[:index])."
          output :collectInto, placeholder: true, group: :advanced, visible: { loopType: "for_each" },
                               description: "Optional list variable that gathers every item the body ran for, " \
                                            "such as the lines that were not skipped."

          validate do |cfg, errors|
            errors.concat(ConditionRules.errors(cfg["condition"], field: "condition", required: true)) if while_loop?(cfg)
            errors.concat(ConditionRules.errors(cfg["stopWhen"], field: "stopWhen"))
            if for_each_loop?(cfg)
              collection_path_errors(cfg, errors)
              errors.concat(ConditionRules.errors(cfg["skipWhen"], field: "skipWhen"))
            end
            header_local_errors(cfg, errors)
          end
        end

        def self.sample_input
          {
            "loopType" => "for_each",
            "collection" => "items",
            "itemVariable" => "item",
            "maxIterations" => 100
          }
        end

        def generate_body
          if value(:loopType).to_s == "for_each"
            generate_for_each_loop
          else
            generate_condition_loop(post_check: value(:runOnceFirst) == true)
          end
        end

        private

        def generate_condition_loop(post_check:)
          max = max_iterations
          condition_check = compile_conditions(value(:condition)) || "true"
          stop_check = compile_conditions(value(:stopWhen))

          lines = []
          seed = post_check ? "{ count: 0, started: false }" : "{ count: 0 }"
          lines.concat(enter_lines(seed))
          lines << "ctx[:_loop_iteration_count] = state[:count]"
          pass = condition_pass_lines(post_check: post_check, max_iterations: max,
            condition_check: condition_check, stop_check: stop_check)
          if loop_has_body?
            lines.concat(pass)
            lines << "true"
          else
            lines << "loop do"
            lines.concat(indent_lines(pass))
            lines << "end"
          end
          lines.join("\n")
        end

        def condition_pass_lines(post_check:, max_iterations:, condition_check:, stop_check:)
          lines = []
          guards = [
            *unless_block(condition_check, leave_return),
            *if_block("state[:count] >= #{max_iterations}", limit_return(max_iterations))
          ]
          if post_check
            lines << "if state[:started]"
            lines.concat(indent_lines(guards))
            lines << "end"
          else
            lines.concat(guards)
          end
          if stop_check
            lines.concat(if_block(stop_check, leave_return))
          end
          lines << "state[:started] = true" if post_check
          lines << "state[:count] += 1"
          lines << "ctx[:_loop_iteration_count] = state[:count]"
          lines
        end

        def generate_for_each_loop
          item_var = loop_ident(:itemVariable, default: "item")
          index_var = loop_ident(:indexVariable, default: "index")
          max = max_iterations
          collector = collect_ident
          skip_check = compile_conditions(value(:skipWhen))
          stop_check = compile_conditions(value(:stopWhen))
          collection_ruby = read(:collection)

          lines = []
          seed = "{ items: #{ensure_array_expr(collection_ruby)}, index: 0, count: 0 }"
          lines.concat(enter_lines(seed))
          lines << "ctx[:#{collector}] ||= []" if collector
          lines << "ctx[:_loop_iteration_count] = state[:count]"
          bind = for_each_bind_lines(item_var, index_var)
          exhausted = if_block("state[:index] >= state[:items].size", leave_return)
          capped = if_block("state[:index] >= #{max}", limit_return(max))
          if loop_has_body?
            lines.concat(exhausted)
            lines.concat(capped)
            lines.concat(bind)
            if skip_check
              lines << "while #{skip_check}"
              lines.concat(indent_lines(exhausted + capped + bind))
              lines << "end"
            end
            lines.concat(if_block(stop_check, leave_return)) if stop_check
            lines << "state[:count] += 1"
            lines << "ctx[:_loop_iteration_count] = state[:count]"
            lines << "ctx[:#{collector}] << #{item_var}" if collector
            lines << "true"
          else
            lines << "while state[:index] < state[:items].size"
            lines.concat(indent_lines(capped + bind))
            lines << "  next if #{skip_check}" if skip_check
            if stop_check
              lines.concat(indent_lines(if_block(stop_check, leave_return)))
            end
            lines << "  state[:count] += 1"
            lines << "  ctx[:_loop_iteration_count] = state[:count]"
            lines << "  ctx[:#{collector}] << #{item_var}" if collector
            lines << "end"
            lines << leave_expr
          end
          lines.join("\n")
        end

        def for_each_bind_lines(item_var, index_var)
          [
            "#{item_var} = state[:items][state[:index]]",
            "#{index_var} = state[:index]",
            "state[:index] += 1",
            "ctx[:#{item_var}] = #{item_var}",
            "ctx[:#{index_var}] = #{index_var}"
          ]
        end

        # The seed block moves onto its own lines when the one-line form would
        # run past the step method's body width.
        def enter_lines(seed)
          inline = "state = #{enter_call} { #{seed} }"
          return [inline] if inline.length <= ENTER_WIDTH

          ["state = #{enter_call} do", "  #{seed}", "end"]
        end

        def enter_call
          args = [":#{state_key}"]
          if loop_execution
            args << "execution: #{literal(loop_execution[:key])}"
            pins = Array(loop_execution[:pins])
            args << "pins: #{literal(pins)}" if pins.any?
          end
          args << "initializers: #{literal(loop_initializers)}" if loop_initializers.any?
          "FlowchartRuntime::Loop.enter(ctx, #{args.join(", ")})"
        end

        def leave_expr
          args = ["ctx", ":#{state_key}"]
          args << literal(loop_exports) if loop_exports.any?
          "FlowchartRuntime::Loop.leave(#{args.join(", ")}) || #{done_signal}"
        end

        def leave_return
          "return #{leave_expr}"
        end

        def limit_expr(max)
          args = ["ctx", ":#{state_key}", "max: #{max}"]
          args << "exports: #{literal(loop_exports)}" if loop_exports.any?
          "FlowchartRuntime::Loop.fail_limit(#{args.join(", ")})"
        end

        def limit_return(max)
          "return #{limit_expr(max)}"
        end

        def if_block(condition, *body)
          [
            "if #{condition}",
            *indent_lines(body.flatten),
            "end"
          ]
        end

        def unless_block(condition, *body)
          [
            "unless #{condition}",
            *indent_lines(body.flatten),
            "end"
          ]
        end

        def indent_lines(lines, depth = 1)
          pad = "  " * depth
          lines.flatten.map { |line| "#{pad}#{line}" }
        end

        def state_key
          raw = (context[:loop_state_key] || context["loop_state_key"]).to_s
          ident = raw.start_with?("_") ? raw : "_#{raw.presence || "loop"}"
          ident.match?(/\A_[a-z_][a-zA-Z0-9_]*\z/) ? ident : "_loop"
        end

        def done_signal
          context[:done_signal].presence || ":done"
        end

        def loop_has_body?
          context[:loop_has_body] == true
        end

        def loop_execution
          context[:loop_execution]
        end

        def loop_initializers
          context[:loop_initializers] || {}
        end

        def loop_exports
          context[:loop_exports] || {}
        end

        def max_iterations
          raw = value(:maxIterations)
          n = raw.is_a?(Integer) ? raw : raw.to_s.to_i
          n = 100 if n <= 0
          [n, MAX_LOOP_ITERATIONS].min
        end

        def loop_ident(field, default:)
          ident = safe_ident(value(field), default: default)
          return default if ident && HEADER_LOCALS.include?(ident)

          ident
        end

        def collect_ident
          raw = value(:collectInto).to_s.strip
          return nil if raw.empty?

          ident = safe_ident(raw, default: nil)
          return nil if ident.nil? || HEADER_LOCALS.include?(ident)

          ident
        end

        def compile_conditions(raw)
          return nil if raw.blank?
          return nil unless raw.is_a?(Hash)

          data = raw.deep_stringify_keys
          return nil unless data["type"] == "group"
          return nil if Array(data["conditions"]).empty?

          build_structured_condition(data)
        end

        def while_loop?(cfg)
          (cfg["loopType"].presence || "while") == "while"
        end

        def collection_path_errors(cfg, errors)
          raw = cfg["collection"].to_s.strip
          return if raw.empty?
          return unless raw.start_with?("ctx.") || raw.start_with?("ctx[")

          errors.add(:collection, :invalid_identifier)
        end

        def for_each_loop?(cfg)
          cfg["loopType"].to_s == "for_each"
        end

        def header_local_errors(cfg, errors)
          return unless for_each_loop?(cfg)

          %w[itemVariable indexVariable].each do |field|
            name = cfg[field].to_s.strip
            next if name.empty?
            unless safe_ident?(name)
              errors.add(field, :invalid_identifier)
              next
            end
            next unless HEADER_LOCALS.include?(name)

            add_loop_error(errors, field, :reserved_header_local, name: name)
          end
          item = loop_ident_from(cfg["itemVariable"], default: "item")
          index = loop_ident_from(cfg["indexVariable"], default: "index")
          if item && index && item == index
            add_loop_error(errors, "itemVariable", :colliding_loop_variables)
          end
        end

        def loop_ident_from(raw, default:)
          ident = safe_ident(raw, default: default)
          return default if ident && HEADER_LOCALS.include?(ident)

          ident
        end

        def add_loop_error(errors, field, code, **vars)
          errors << CodeGenerators::ConfigError.new(
            field: field.to_s,
            code: code.to_sym,
            message: I18n.t("flowchart_elements.loop.errors.#{code}", field: field, **vars)
          )
        end
      end
    end
  end
end
