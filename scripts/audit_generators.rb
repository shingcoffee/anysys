#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Audits every in-scope code generator against the canonical Trailblazer Railway
# shape. Emits a machine-readable YAML gap report at
#   docs/superpowers/specs/2026-04-27-generator-audit-data.yml
#
# Rules checked (see docs/superpowers/specs/2026-04-27-code-generator-canonical-alignment-design.md):
#   2. bracket-notation ctx access
#   4. no inline multi-step orchestration
#   5. no legacy alias reads
#   7. enum validation uses fetch_enum
#   8. dependencies reflects ctx reads
#   9. no forbidden emitted source
#
# Usage (from repo root):
#   bundle exec ruby scripts/audit_generators.rb           # exits non-zero on gaps
#   bundle exec rake audit:generators                       # same, via rake
#   bundle exec rake audit:generators:baseline              # regenerates baseline YAML

require_relative "../config/environment" unless defined?(Rails)
require "ripper"
require "yaml"
require "pathname"
require "set"

module GeneratorAudit
  BASELINE_PATH = Rails.root.join("docs/superpowers/specs/2026-04-27-generator-audit-data.yml")
  GENERATORS_ROOT = Rails.root.join("app/services/code_generators/element_types")
  # Mandatory single-option variants are uncapped. This cap applies only to
  # additional pairwise variants for each generator.
  MAX_PAIRWISE_VARIANTS_PER_GENERATOR = 64

  class UnusableOutputError < StandardError; end

  FORBIDDEN_EMISSION = {
    net_http: /\bNet::HTTP\b/,
    raw_cipher: /\bOpenSSL::Cipher\b/,
    optional_dependency: /defined\?\((?:Zip|Barby|RQRCode|Liquid|Loofah|MiniMagick)\)/,
    unsafe_eval: /\b(?:eval|class_eval)\s*\(/,
    unsafe_marshal: /\bMarshal\.load\b/,
    unsafe_yaml: /\bYAML\.(?:load|unsafe_load)\b/
  }.freeze

  # Map of ctx keys that are canonically written by specific generators.
  CTX_PRODUCERS = {
    "contract"       => :build_contract,
    "model"          => :new_model,
    "routed_params"  => :detect_and_route_params,
    "valid"          => :validate_contract
  }.freeze

  DEPENDENCY_CHAIN = {
    validate_contract: [:build_contract],
    build_contract:    [:new_model],
    populate_primary:  [:new_model, :detect_and_route_params],
    populate_associations: [:detect_and_route_params]
  }.freeze

  AMBIENT_CTX_KEYS = %w[
    bound_entity customer_id current_user current_user_id current_user_role audience
    params request response session flash headers id page per_page limit offset sort filter q
  ].to_set.freeze

  class << self
    def run_audit
      report = {}
      generator_files.each do |file|
        klass = load_generator(file)
        next unless klass

        gaps = check_generator(klass)
        report[klass.name] = {
          file: relative_path(file),
          gaps: gaps
        }
      end
      report
    end

    def check_generator(klass)
      source_file = source_path_for(klass)
      return [] unless source_file && File.exist?(source_file)

      source = File.read(source_file)
      ast = Ripper.sexp(source)

      gaps = []
      gaps.concat(check_legacy_aliases(ast, klass))
      gaps.concat(check_enum_handling(source, klass))
      generated_variants(klass).each do |variant|
        if variant[:generation_error]
          gaps << variant.fetch(:generation_error)
          next
        end

        body = variant.fetch(:body)
        label = variant.fetch(:label)
        element = variant.fetch(:element)
        gaps.concat(label_variant(check_ctx_access(body, klass), label))
        gaps.concat(label_variant(check_orchestration(body, klass), label))
        gaps.concat(label_variant(check_dependencies(body, klass, element), label))
        gaps.concat(label_variant(check_forbidden_emission(source, body, klass), label))
      end
      gaps
    end

    def write_baseline(report)
      serialized = report.each_with_object({}) do |(name, entry), out|
        out[name] = {
          "file" => entry[:file],
          "gaps" => entry[:gaps].map { |g| g.transform_keys(&:to_s) }
        }
      end
      File.write(BASELINE_PATH, serialized.to_yaml)
    end

    private

    # --- rule implementations ---------------------------------------------

    def check_forbidden_emission(source, body, klass)
      allowed = source_allow_directives(source)
      emitted_source = executable_emitted_source(body)

      gaps = []
      FORBIDDEN_EMISSION.each do |rule, pattern|
        next unless emitted_source.match?(pattern)

        if allowed.key?(rule)
          gaps << {
            rule: rule,
            message: "Allowed exception for #{rule}: #{allowed[rule]}",
            file: relative_source(klass),
            allowed: true,
            reason: allowed[rule]
          }
        else
          gaps << {
            rule: rule,
            message: "Forbidden pattern detected in emitted body (#{rule}): #{pattern.inspect}",
            file: relative_source(klass)
          }
        end
      end

      gaps
    end

    def source_allow_directives(source)
      Ripper.lex(source.to_s).each_with_object({}) do |(_position, token_type, token, _state), allowed|
        next unless token_type == :on_comment
        next unless token =~ /\A#\s*generator-audit:\s*allow\s+(?<rule>\w+)\s+--\s+(?<reason>.+?)\s*\z/

        allowed[Regexp.last_match[:rule].to_sym] = Regexp.last_match[:reason]
      end
    end

    def executable_emitted_source(body)
      ignored_tokens = %i[
        on_comment on_embdoc on_embdoc_beg on_embdoc_end on_tstring_content
      ].freeze

      Ripper.lex(body.to_s).filter_map do |_position, token_type, token, _state|
        token unless ignored_tokens.include?(token_type)
      end.join
    end

    def check_ctx_access(body, klass)
      return [] if body.nil?

      matches = body.scan(/\bctx\.(?!dig\b|\[)[a-zA-Z_][a-zA-Z_0-9]*/)
      return [] if matches.empty?

      [{
        rule: :ctx_access,
        message: "Body reads ctx via dotted access instead of ctx[:key]: #{matches.uniq.join(', ')}",
        file: relative_source(klass)
      }]
    end

    def check_orchestration(body, klass)
      return [] if body.nil?

      activity_calls = body.scan(/ActivitySteps::[A-Z][A-Za-z0-9_]*\.call/).size
      return [] if activity_calls.zero?

      if activity_calls >= 2
        return [{
          rule: :inline_orchestration,
          message: "Body contains multiple (#{activity_calls}) ActivitySteps:: orchestration calls — each orchestration call is a separate step.",
          file: relative_source(klass)
        }]
      end

      meaningful_lines = body.lines.map(&:strip).reject { |l| l.empty? || l == "true" }
      if meaningful_lines.size > 1
        return [{
          rule: :inline_orchestration,
          message: "Body mixes an ActivitySteps:: call with additional logic (#{meaningful_lines.size} meaningful lines). Either make the body a thin wrapper (just the ActivitySteps:: call) or split the extra logic into its own step.",
          file: relative_source(klass)
        }]
      end

      []
    end

    def check_legacy_aliases(ast, klass)
      violations = []
      walk(ast) do |node|
        next unless node.is_a?(Array) && node[0] == :binary && node[2] == :"||"
        left = extract_config_key(node[1])
        right = extract_config_key(node[3])
        next unless left && right

        violations << "config[#{left.inspect}] || config[#{right.inspect}]"
      end
      return [] if violations.empty?

      [{
        rule: :legacy_alias,
        message: "Legacy-alias fallback pattern detected: #{violations.uniq.join('; ')}. Pick the canonical key, drop the alias, rename the UI field.",
        file: relative_source(klass)
      }]
    end

    def check_enum_handling(source, klass)
      offenders = []
      ast = Ripper.sexp(source)

      walk(ast) do |node|
        method_name, body = method_definition(node)
        next unless method_name && body
        next if method_name == "validate_config"
        next unless method_name.start_with?("generate_", "build_")

        word_array_include_lines(body).each do |lineno|
          offenders << "#{relative_source(klass)}:#{lineno} in ##{method_name}"
        end
      end
      return [] if offenders.empty?

      [{
        rule: :enum_handling,
        message: "Hand-rolled enum check (%w[...].include?) inside generate_* / build_* method — use fetch_enum. Offenders: #{offenders.join('; ')}",
        file: relative_source(klass)
      }]
    end

    def check_dependencies(body, klass, element)
      return [] if body.nil?

      declared = Array(safely_call(klass, :dependencies, element) || []).map(&:to_sym).to_set
      effective = expand_dependencies(declared)
      ctx_reads = body.scan(/ctx\[:([a-zA-Z_][a-zA-Z_0-9]*)\](?!\s*=(?![=~>]))/).flatten.uniq
      missing = []
      ctx_reads.each do |key|
        next if AMBIENT_CTX_KEYS.include?(key)
        producer = CTX_PRODUCERS[key]
        next unless producer
        next if effective.include?(producer)

        missing << "reads ctx[:#{key}] (produced by :#{producer}) but :#{producer} not in dependencies (direct or transitive)"
      end
      return [] if missing.empty?

      [{
        rule: :dependencies,
        message: missing.join('; '),
        file: relative_source(klass)
      }]
    end

    # --- helpers ---------------------------------------------------------

    def expand_dependencies(declared)
      seen = Set.new
      stack = declared.to_a
      until stack.empty?
        dep = stack.pop
        next if seen.include?(dep)
        seen << dep
        Array(DEPENDENCY_CHAIN[dep]).each { |t| stack.push(t) unless seen.include?(t) }
      end
      seen
    end

    def generator_files
      CodeGenerators::GeneratorRegistry.instance.all_generators.values.uniq.filter_map do |klass|
        source_path_for(klass)
      end.sort
    end

    def load_generator(file)
      require file
      name = file_to_class_name(file)
      name.constantize
    rescue NameError, LoadError => e
      warn "Failed to load generator #{file}: #{e.message}"
      nil
    end

    def file_to_class_name(file)
      rel = Pathname.new(file).relative_path_from(Rails.root.join("app/services"))
      rel.to_s.delete_suffix(".rb").camelize
    end

    def source_path_for(klass)
      method_source_location = klass.instance_method(:generate_body).source_location
      method_source_location && method_source_location[0]
    end

    def generated_variants(klass)
      seen_bodies = Set.new

      configuration_variants(klass).filter_map do |variant|
        element = build_sample_element(klass, variant.fetch(:config))
        generated = generate_body_safely(klass, element, variant.fetch(:label))
        next generated if generated[:generation_error]

        body = generated.fetch(:body)
        next if seen_bodies.include?(body)

        seen_bodies << body
        { label: variant.fetch(:label), body: body, element: element }
      end
    end

    def configuration_variants(klass)
      sample = deep_dup(klass.respond_to?(:sample_input) ? klass.sample_input : {})
      ui_fields = ui_config_fields_for(klass)
      variants = []
      seen_configs = Set.new
      sample_config = build_scenario_config(klass, sample, {}, ui_fields)
      append_configuration_variant(variants, seen_configs, klass, "sample_input", sample_config)
      fields = variant_fields(klass, ui_fields)

      fields.each do |field|
        field.fetch(:values).each do |value|
          overrides = { field.fetch(:name) => value }
          config = build_scenario_config(klass, sample, overrides, ui_fields)
          append_configuration_variant(
            variants,
            seen_configs,
            klass,
            "#{field.fetch(:name)}=#{variant_value_label(value)}",
            config
          )
        end
      end

      retained_pairwise = 0
      pairwise_variant_candidates(fields).each do |candidate|
        break if retained_pairwise >= MAX_PAIRWISE_VARIANTS_PER_GENERATOR

        config = build_scenario_config(klass, sample, candidate.fetch(:overrides), ui_fields)
        retained = append_configuration_variant(
          variants,
          seen_configs,
          klass,
          candidate.fetch(:label),
          config
        )
        retained_pairwise += 1 if retained
      end

      variants
    end

    def schema_variant_values(klass)
      variant_fields(klass).to_h { |field| [field.fetch(:name), field.fetch(:values)] }
    end

    def variant_fields(klass, ui_fields = ui_config_fields_for(klass))
      ui_by_key = ui_fields.to_h { |field| [(field[:key] || field["key"]).to_s, field] }
      conditional_values = conditional_ui_variant_values(klass, ui_fields)
      conditional_triggers = conditional_ui_trigger_values(klass, ui_fields)
      fields = []
      field_indexes = {}

      generator_config_fields(klass).each_value do |field|
        name = field.fetch(:name).to_s
        type = (field[:type] || field[:role] || :string).to_sym
        type = :boolean if type == :flag
        allowed = field[:values] || field.dig(:options, :values)
        ui_field = ui_by_key[name]
        values = serialized_variant_values(type, allowed, ui_field)
        values.concat(Array(conditional_values[name]))

        field_indexes[name] = fields.length
        fields << {
          name: name,
          type: type,
          values: values.uniq,
          default: serialized_field_default(ui_field, klass, name),
          conditional_trigger_values: Array(conditional_triggers[name]).to_set
        }
      end

      conditional_values.each do |name, values|
        next if field_indexes.key?(name)

        ui_field = ui_by_key[name]
        fields << {
          name: name,
          type: :conditional,
          values: values.uniq,
          default: serialized_field_default(ui_field, klass, name),
          conditional_trigger_values: Array(conditional_triggers[name]).to_set
        }
      end

      fields.reject { |field| field.fetch(:values).empty? }
    end

    def serialized_variant_values(type, allowed, ui_field)
      options = Array(ui_field && (ui_field[:options] || ui_field["options"]))
      serialized_options = options.filter_map { |option| hash_value(option, :value) }

      if type == :boolean
        [true, false]
      elsif !serialized_options.empty?
        serialized_options
      elsif type == :enum || allowed
        Array(allowed).dup
      else
        []
      end
    end

    def serialized_field_default(ui_field, klass, name)
      if ui_field
        default = hash_value(ui_field, :default)
        return default unless default.nil?
      end

      sample = klass.respond_to?(:sample_input) ? klass.sample_input : {}
      return sample[name] if sample.key?(name)

      sample[name.to_sym]
    end

    # Singles are exhaustive. Pairwise variants are bounded globally to keep
    # the audit fast, with conditional anchors and boolean+enum branches first.
    def pairwise_variant_candidates(fields)
      sequence = 0

      fields.combination(2).flat_map do |left, right|
        left_values = non_default_values(left)
        right_values = non_default_values(right)

        left_values.product(right_values).map do |left_value, right_value|
          sequence += 1
          {
            priority: pairwise_priority(left, left_value, right, right_value),
            sequence: sequence,
            overrides: {
              left.fetch(:name) => left_value,
              right.fetch(:name) => right_value
            },
            label: "#{left.fetch(:name)}=#{variant_value_label(left_value)} + " \
                   "#{right.fetch(:name)}=#{variant_value_label(right_value)}"
          }
        end
      end.sort_by { |candidate| [candidate.fetch(:priority), candidate.fetch(:sequence)] }
    end

    def pairwise_priority(left, left_value, right, right_value)
      types = [left.fetch(:type), right.fetch(:type)]
      return 0 if left.fetch(:conditional_trigger_values).include?(left_value)
      return 0 if right.fetch(:conditional_trigger_values).include?(right_value)
      return 1 if types.include?(:boolean) && types.include?(:enum)
      return 2 if types.include?(:boolean)

      3
    end

    def non_default_values(field)
      field.fetch(:values).reject { |value| value == field[:default] }
    end

    def append_configuration_variant(variants, seen_configs, klass, label, config)
      return unless seen_configs.add?(config)
      return unless validation_passes?(klass, config)

      variants << { label: label, config: config }
      true
    end

    def hash_value(hash, key)
      return hash[key] if hash.key?(key)

      hash[key.to_s]
    end

    def conditional_ui_variant_values(klass, fields = ui_config_fields_for(klass))
      by_key = fields.to_h { |field| [(field[:key] || field["key"]).to_s, field] }
      anchors = conditional_ui_trigger_values(klass, fields).transform_values(&:dup)

      anchors.each do |anchor, allowed|
        field = by_key[anchor]
        options = Array(field && (field[:options] || field["options"]))
        allowed.concat(options.filter_map { |option| hash_value(option, :value) })
      end

      anchors.transform_values(&:uniq)
    end

    def conditional_ui_trigger_values(klass, fields = ui_config_fields_for(klass))
      anchors = Hash.new { |hash, key| hash[key] = [] }

      fields.each do |field|
        visibility = field[:visibleWhen] || field["visibleWhen"]
        next unless visibility.is_a?(Hash)

        anchor = (visibility[:field] || visibility["field"]).to_s
        next if anchor.empty?

        anchors[anchor].concat(Array(visibility[:values] || visibility["values"]))
        value = hash_value(visibility, :value)
        anchors[anchor] << value unless value.nil?
      end

      anchors.transform_values(&:uniq)
    end

    def build_scenario_config(klass, sample, overrides, ui_fields)
      config = deep_dup(sample)
      overrides.each { |field, value| config[field.to_s] = deep_dup(value) }
      generator_fields = generator_config_fields(klass)

      populate_unconditional_required_fields(config, ui_fields, generator_fields)
      populate_visible_dependent_fields(config, ui_fields, overrides.keys.map(&:to_s), generator_fields)
      config
    end

    def populate_unconditional_required_fields(config, ui_fields, generator_fields)
      ui_fields.each do |field|
        next unless hash_value(field, :required)
        next if hash_value(field, :visibleWhen)

        populate_scenario_field(config, field, generator_fields)
      end

      ui_keys = ui_fields.to_set { |field| hash_value(field, :key).to_s }
      generator_fields.each_value do |field|
        next unless field[:required]
        next if ui_keys.include?(field.fetch(:name))

        populate_scenario_field(config, field, generator_fields)
      end
    end

    def populate_visible_dependent_fields(config, ui_fields, overridden_fields, generator_fields)
      active_anchors = overridden_fields.to_set

      loop do
        changed = false
        ui_fields.each do |field|
          visibility = hash_value(field, :visibleWhen)
          next unless visibility.is_a?(Hash)

          anchor = hash_value(visibility, :field).to_s
          next unless active_anchors.include?(anchor)
          next unless visibility_matches?(visibility, config[anchor])

          key = hash_value(field, :key).to_s
          populated = populate_scenario_field(config, field, generator_fields)
          next unless populated || scenario_value_present?(config[key])

          newly_active = active_anchors.add?(key)
          changed = true if populated || newly_active
        end
        break unless changed
      end
    end

    def populate_scenario_field(config, field, generator_fields)
      key = (hash_value(field, :key) || field[:name]).to_s
      return false if key.empty? || scenario_value_present?(config[key])

      value = representative_value(field, generator_fields[key])
      # A value that never counts as present would be repopulated forever by
      # populate_visible_dependent_fields.
      return false unless scenario_value_present?(value)

      config[key] = deep_dup(value)
      true
    end

    def representative_value(field, generator_field)
      schema_default = hash_value(field, :default)
      return schema_default if scenario_value_present?(schema_default)

      generator_default = generator_field && generator_field[:default]
      return generator_default if scenario_value_present?(generator_default)

      type = (hash_value(field, :type) || generator_field&.dig(:role) || generator_field&.dig(:type)).to_s
      case type
      when "text", "textarea", "expression", "string", "literal", "input", "output",
           "template", "entity_attribute", "reference", "localized_text"
        "audit_value"
      when "number", "integer", "decimal"
        hash_value(field, :min) || generator_field&.dig(:min) || 1
      when "select", "radio", "enum"
        options = Array(hash_value(field, :options))
        options.filter_map { |option| hash_value(option, :value) }
          .find { |value| scenario_value_present?(value) } ||
          Array(generator_field && generator_field[:values])
            .find { |value| scenario_value_present?(value) }
      when "checkbox", "boolean", "flag"
        true
      when "key_value_list", "mapping", "list"
        [{ "key" => "audit", "value" => "audit_value" }]
      when "conditions"
        {
          "type" => "group",
          "joins" => [],
          "conditions" => [{ "kind" => "field", "leftOperand" => "ctx.audit", "operator" => "is_true", "rightOperand" => "" }]
        }
      end
    end

    def generator_config_fields(klass)
      catalog = Array(klass.respond_to?(:config_fields) ? klass.config_fields : [])
      fields = catalog.to_h do |field|
        name = (field[:name] || field["name"]).to_s
        [name, field.transform_keys(&:to_sym).merge(name: name)]
      end

      schema = klass.respond_to?(:_config_schema) ? klass._config_schema : nil
      Array(schema&.fields).each do |field|
        fields[field.name] = merge_declared_field(fields.fetch(field.name, {}), field)
      end
      fields
    end

    def merge_declared_field(existing, field)
      opts = field.options || {}
      existing.merge(
        name: field.name,
        type: field.role,
        role: field.role,
        values: opts[:values],
        required: opts[:required],
        default: opts[:default],
        min: opts[:min]
      )
    end

    def validation_passes?(klass, config)
      element = build_sample_element(klass, config)
      validation = klass.new(element, {}).validate_config(element_config(klass, element))
      validation.is_a?(Array) && validation.empty?
    rescue StandardError
      false
    end

    def visibility_matches?(visibility, actual)
      expected = Array(hash_value(visibility, :values))
      value = hash_value(visibility, :value)
      expected << value unless value.nil?
      expected.any? { |candidate| candidate.to_s == actual.to_s }
    end

    def scenario_value_present?(value)
      return false if value.nil?
      return !value.empty? if value.respond_to?(:empty?)

      true
    end

    def ui_config_fields_for(klass)
      CodeGenerators::Shared::SchemaReader.read(klass.generator_name)
    end

    def generate_body_safely(klass, element, label)
      generator = klass.new(element, {})
      body = generator.generate_body
      unless body.nil? || body.is_a?(String)
        raise UnusableOutputError, "generate_body returned #{body.class}; expected String or nil"
      end

      { body: body }
    rescue StandardError => e
      {
        generation_error: {
          rule: :generation_error,
          generator: klass.name,
          variant: label,
          exception_class: e.class.name,
          exception_message: e.message,
          message: "Could not generate #{klass.name} variant #{label}: #{e.class}: #{e.message}",
          file: relative_source(klass)
        }
      }
    end

    def element_config(klass, element)
      element_kind = klass.respond_to?(:generator_kind) ? klass.generator_kind : :step_action
      element_kind == :element_type ? element.fetch("properties", {}) : element.fetch("config", {})
    end

    def build_sample_element(klass, config = nil)
      sample = config || (klass.respond_to?(:sample_input) ? klass.sample_input : {})
      element_kind = klass.respond_to?(:generator_kind) ? klass.generator_kind : :step_action
      if element_kind == :element_type
        { "id" => "audit", "type" => klass.generator_name, "properties" => sample }
      else
        { "id" => "audit", "type" => "process", "config" => sample }
      end
    end

    def safely_call(klass, method, element = build_sample_element(klass))
      klass.new(element, {}).send(method)
    rescue StandardError
      nil
    end

    def label_variant(gaps, label)
      gaps.map { |gap| gap.merge(variant: label) }
    end

    def variant_value_label(value)
      value.is_a?(String) ? value : value.inspect
    end

    def deep_dup(value)
      case value
      when Hash
        value.to_h { |key, item| [key, deep_dup(item)] }
      when Array
        value.map { |item| deep_dup(item) }
      else
        value.dup
      end
    rescue TypeError
      value
    end

    def extract_config_key(node)
      return nil unless node.is_a?(Array)
      return nil unless node[0] == :aref

      receiver = node[1]
      return nil unless receiver.is_a?(Array)
      return nil unless receiver[0] == :vcall || receiver[0] == :var_ref

      ident = dig_array(receiver, [1, 1])
      return nil unless %w[config cfg].include?(ident)

      args = node[2]
      return nil unless args.is_a?(Array) && args[0] == :args_add_block

      string_literal = args[1].is_a?(Array) ? args[1][0] : nil
      return nil unless string_literal.is_a?(Array) && string_literal[0] == :string_literal

      string_content = string_literal[1]
      return nil unless string_content.is_a?(Array) && string_content[0] == :string_content

      tstring = string_content[1]
      return nil unless tstring.is_a?(Array) && tstring[0] == :@tstring_content

      tstring[1]
    end

    def method_definition(node)
      return [nil, nil] unless node.is_a?(Array)

      case node[0]
      when :def
        [node.dig(1, 1), node[3]]
      when :defs
        [node.dig(3, 1), node[5]]
      else
        [nil, nil]
      end
    end

    def word_array_include_lines(node, lines = [])
      return lines unless node.is_a?(Array)
      return lines if %i[def defs].include?(node[0])

      lines << node.dig(3, 2, 0) if word_array_include_call?(node)
      node.each { |child| word_array_include_lines(child, lines) if child.is_a?(Array) }
      lines
    end

    def word_array_include_call?(node)
      return false unless node[0] == :call

      receiver = node[1]
      method_token = node[3]
      return false unless method_token.is_a?(Array) && method_token[1] == "include?"
      return false unless receiver.is_a?(Array) && receiver[0] == :array

      words = receiver[1]
      words.is_a?(Array) && !words.empty? &&
        words.all? { |word| word.is_a?(Array) && word[0] == :@tstring_content }
    end

    def walk(node, &block)
      return unless node.is_a?(Array)
      yield node
      node.each { |child| walk(child, &block) if child.is_a?(Array) }
    end

    def dig_array(node, path)
      path.inject(node) { |acc, idx| acc.is_a?(Array) ? acc[idx] : nil }
    end

    def relative_path(file)
      Pathname.new(file).relative_path_from(Rails.root).to_s
    end

    def relative_source(klass)
      path = source_path_for(klass)
      path ? relative_path(path) : klass.name
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  report = GeneratorAudit.run_audit
  GeneratorAudit.write_baseline(report)
  actionable = report.sum { |_, entry| entry[:gaps].reject { |g| g[:allowed] || g["allowed"] }.size }
  puts "Wrote audit report with #{report.size} generators and #{actionable} actionable gaps to #{GeneratorAudit::BASELINE_PATH}"
  exit(actionable.zero? ? 0 : 1)
end
