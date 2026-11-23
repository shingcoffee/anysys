# frozen_string_literal: true

class ActivityGenerator
  # Lays out the generated Railway class: the CANVAS map back to the editor,
  # the Routes signal constants, the step declarations with their wiring, the
  # step methods and the failure-track collect_errors.
  class ClassRenderer
    # The class body is indented one level.
    WIDTH = CodeGenerators::SourceFormatter::STEP_WIDTH

    def initialize(class_name:, steps:, canvas:, method_sources:)
      @class_name = class_name
      @steps = steps
      @canvas = canvas
      @method_sources = method_sources
    end

    def render
      sections = [canvas_source, routes_source, declarations_source, methods_source].compact
      "class #{@class_name} < Trailblazer::Activity::Railway\n#{sections.join("\n\n").indent(2)}\nend\n"
    end

    private

    def canvas_source
      entries = @canvas.select { |key, value| key == :steps || value.present? }
      lines = entries.map { |key, value| "#{key}: #{hash_literal(value)}" }
      CodeGenerators::SourceFormatter.call("CANVAS = {\n#{lines.join(",\n").indent(2)}\n}.freeze", max_width: WIDTH)
    end

    # Keys are generated step names and route semantics, so always plain labels.
    def hash_literal(hash)
      pairs = hash.map { |key, value| "#{key}: #{value.is_a?(Hash) ? hash_literal(value) : value.to_s.inspect}" }
      pairs.empty? ? "{}" : "{ #{pairs.join(', ')} }"
    end

    def routes_source
      routed = @steps.select(&:route_module)
      return if routed.empty?

      modules = routed.map do |step|
        constants = step.route_constants.map { |name| "  #{name} = Class.new(Trailblazer::Activity::Signal)" }
        ["module #{step.route_module}", *constants, "end"].join("\n")
      end
      "module Routes\n#{modules.join("\n").indent(2)}\nend"
    end

    def declarations_source
      [*@steps.map { |step| declaration(step) }, "fail :collect_errors"].join("\n")
    end

    # Wiring stays on the declaration line unless a router has several
    # outputs, a subflow maps inputs, or the line would run past the width.
    def declaration(step)
      head = if step.subprocess
        "step Subprocess(#{step.subprocess[:activity_class_name]}), id: :#{step.method_name}"
      else
        "step :#{step.method_name}"
      end
      mapping = Array(step.subprocess&.dig(:variable_mapping))
      parts = mapping + wiring(step)
      return head if parts.empty?

      inline = "#{head}, #{parts.join(", ")}"
      router = step.decision? || step.loop?
      return inline unless (router && parts.size > 1) || mapping.any? || inline.length > WIDTH

      "#{head},\n  #{parts.join(",\n  ")}"
    end

    def wiring(step)
      parts = []
      parts << "magnetic_to: nil" if step.magnetic == false
      Array(step.outputs).each { |left, right| parts << "#{left} => #{right}" }
      parts
    end

    def methods_source
      [*@method_sources, collect_errors_source].join("\n\n")
    end

    # Loop headers keep iteration state in ctx; a failed run must not leak it.
    def collect_errors_source
      clears = @steps.select(&:loop?).map { |step| "ctx.delete(:_#{step.method_name})" }
      body = [*clears, "ctx[:errors] = FlowchartRuntime::Errors.collect(ctx)"].join("\n")
      "def collect_errors(ctx, **)\n#{body.indent(2)}\nend"
    end
  end
end
