# frozen_string_literal: true

class ActivityGenerator
  # Derives Ruby-safe class and method names from user-supplied flowchart and
  # element labels. All name-collision and reserved-word handling lives here.
  class NameDeriver
    # Ruby reserved words that cannot appear as class/method identifiers.
    RUBY_RESERVED_WORDS = %w[
      BEGIN END alias and begin break case class def defined? do else elsif
      end ensure false for if in module next nil not or redo rescue retry
      return self super then true undef unless until when while yield
      __FILE__ __LINE__ __ENCODING__
    ].freeze

    RESERVED_METHOD_NAMES = (
      RUBY_RESERVED_WORDS +
      Trailblazer::Activity::Railway.new.public_methods.map(&:to_s) +
      Trailblazer::Activity::Railway.new.private_methods.map(&:to_s) +
      %w[collect_errors]
    ).to_set.freeze

    TYPE_COUNTERS_KEY = :__type_counters
    ASCII_LETTER_RE = /[A-Za-z]/
    WORD_SPLIT_RE = /[^A-Za-z0-9]+/

    # Convert a flowchart name into a valid Ruby constant (PascalCase + Activity suffix).
    # The name alone decides it: a parent derives its subflow's class from the
    # child's name, and an activity is compiled before its record has an id.
    # Names without Latin letters (e.g. Chinese) get a digest of the name.
    def derive_activity_class_name(name)
      words = ascii(name).split(WORD_SPLIT_RE).reject(&:empty?)
      base = words.map(&:capitalize).join
      base = "Flowchart#{Digest::SHA256.hexdigest(name.to_s)[0, 10]}" if base.empty?
      base = "Flow#{base}" if base =~ /\A\d/

      class_name = "#{base}Activity"
      class_name = "#{class_name}Flow" if RUBY_RESERVED_WORDS.include?(class_name)

      class_name
    end

    # Derive a unique snake_case method name for an element.
    # @param element [Hash]
    # @param used_names [Hash] mutable tracking map shared across the DFS walk
    def derive_method_name(element, used_names)
      base_name = extract_base_name(element, used_names)
      ensure_unique_name(base_name, used_names)
    end

    # Camelized Routes module name for a decision step, unique within +used_modules+.
    def derive_route_module_name(step_name, used_modules)
      words = step_name.to_s.split(WORD_SPLIT_RE).reject(&:empty?)
      base = words.map { |word| word[0].upcase + word[1..] }.join
      base = "Decision" if base.empty?
      uniquify_constant(base, used_modules)
    end

    # Preview outgoing_branches for DecisionGenerator when topology steps
    # have not been assigned yet (element preview / ConfigValidator).
    def self.outgoing_branches(element, connections)
      new.outgoing_branches(element, connections)
    end

    def outgoing_branches(element, connections)
      used_names = {}
      used_modules = {}
      step_name = derive_method_name(element, used_names)
      _module_name, branches = bind_branches(connections, step_name: step_name, used_modules: used_modules)
      branches.map { |branch|
        {
          "signal" => branch[:signal],
          "semantic" => branch[:semantic].to_s,
          "matchValue" => branch[:match_value]
        }
      }
    end

    def self.port_index(connection)
      match = connection.to_h.stringify_keys["fromPort"].to_s.match(/\Aport_(\d+)\z/)
      match ? Integer(match[1]) : Float::INFINITY
    end

    def self.order_by_port(connections)
      Array(connections).each_with_index.sort_by { |connection, index|
        [port_index(connection), index]
      }.map(&:first)
    end

    # Bind canvas connections to Routes::<Module>::<Const> identities.
    # Branch order follows connection fromPort (port_N), not array order.
    # @return [Array(String, Array<Hash>)] module name plus branch hashes
    def bind_branches(connections, step_name:, used_modules:)
      connections = self.class.order_by_port(connections)
      module_name = derive_route_module_name(step_name, used_modules)
      names = derive_branch_names(connections.map { |connection| connection["matchValue"] })
      branches = connections.zip(names).map do |connection, name|
        {
          semantic: name[:semantic],
          signal: "Routes::#{module_name}::#{name[:const_name]}",
          const_name: name[:const_name],
          target: connection["to"],
          connection_id: connection["id"],
          match_value: connection["matchValue"]
        }
      end
      [module_name, branches]
    end

    # Bind a loop header's exit connection to Routes::<Module>::Done.
    def bind_loop_done(exit_connection, step_name:, used_modules:)
      module_name = derive_route_module_name(step_name, used_modules)
      [module_name, {
        semantic: :done,
        signal: "Routes::#{module_name}::Done",
        const_name: "Done",
        target: exit_connection && exit_connection["to"],
        connection_id: exit_connection && exit_connection["id"]
      }]
    end

    # Per-connection branch constant + semantic from match values (spec A2).
    # @param match_values [Array] connection matchValue list in canvas order
    # @return [Array<Hash>] { const_name:, semantic:, match_value: }
    def derive_branch_names(match_values)
      used_const = {}
      used_semantic = {}
      Array(match_values).each_with_index.map do |raw, index|
        const_name, semantic = branch_identity(raw, index)
        {
          const_name: uniquify_constant(const_name, used_const),
          semantic: uniquify_semantic(semantic, used_semantic),
          match_value: raw
        }
      end
    end

    private

    def branch_identity(raw, index)
      stripped = raw.to_s.strip
      down = stripped.downcase
      return %w[Yes yes] if down == "true"
      return %w[No no] if down == "false"
      return %w[Otherwise otherwise] if stripped.empty?
      return ["SuccessBranch", "success_branch"] if down == "success"
      return ["FailureBranch", "failure_branch"] if down == "failure"
      return ["Branch#{index + 1}", "branch_#{index + 1}"] unless stripped.match?(/[A-Za-z0-9]/)

      words = stripped.split(WORD_SPLIT_RE).reject(&:empty?)
      const_name = words.map { |word| word[0].upcase + word[1..] }.join
      semantic = stripped.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/^_|_$/, "")
      if const_name.match?(/\A\d/) || semantic.match?(/\A\d/)
        const_name = "Value#{const_name}"
        semantic = "value_#{semantic}"
      end
      [const_name, semantic]
    end

    def uniquify_constant(name, used)
      return name.tap { used[name] = 0 } unless used.key?(name)

      suffix = 2
      loop do
        candidate = "#{name}#{suffix}"
        unless used.key?(candidate)
          used[candidate] = 0
          return candidate
        end
        suffix += 1
      end
    end

    def uniquify_semantic(name, used)
      return name.to_sym.tap { used[name] = 0 } unless used.key?(name)

      suffix = 2
      loop do
        candidate = "#{name}_#{suffix}"
        unless used.key?(candidate)
          used[candidate] = 0
          return candidate.to_sym
        end
        suffix += 1
      end
    end

    def extract_base_name(element, used_names)
      label = element["label"].presence && ascii(element["label"])
      return next_type_name(element["type"], used_names) if label && !label.match?(ASCII_LETTER_RE)
      return next_type_name(element["type"], used_names) if label.blank? && !element["type"].to_s.match?(ASCII_LETTER_RE)

      normalize_method_name(label || element["type"])
    end

    # "Café" reads as "Cafe"; characters with no Latin form become "?". The
    # locale is pinned so a class name never depends on who compiled it.
    def ascii(text)
      ActiveSupport::Inflector.transliterate(text.to_s.scrub, locale: :en)
    end

    def next_type_name(type, used_names)
      counters = used_names[TYPE_COUNTERS_KEY] ||= {}
      key = type.to_s.presence || "step"
      counters[key] = counters.fetch(key, 0) + 1
      "#{key}_#{counters[key]}"
    end

    def normalize_method_name(name)
      normalized = name.to_s
                       .downcase
                       .gsub(/[^a-z0-9]+/, "_")
                       .gsub(/^_|_$/, "")
                       .then { |n| n.empty? ? "step" : n }

      normalized = "s_#{normalized}" if normalized =~ /\A\d/
      normalized = "#{normalized}_step" if RESERVED_METHOD_NAMES.include?(normalized)

      normalized
    end

    def ensure_unique_name(base_name, used_names)
      unless used_names.key?(base_name)
        used_names[base_name] = 0
        return base_name
      end

      loop do
        used_names[base_name] += 1
        candidate = "#{base_name}_#{used_names[base_name]}"
        next if used_names.key?(candidate)

        used_names[candidate] = 0
        return candidate
      end
    end
  end
end
