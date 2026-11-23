#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Audits every in-scope code generator against the UI property-editor schema.
# Emits a machine-readable YAML gap report at
#   docs/superpowers/specs/2026-04-19-generator-ui-audit-data.yml
#
# Usage (from repo root):
#   bundle exec ruby scripts/audit_generator_ui.rb

require_relative "../config/environment" if defined?(Rails) || File.exist?("config/environment.rb")
require "yaml"
require "ripper"
require "pathname"
require "set"
require "open3"
require "json"

OUTPUT_PATH = Rails.root.join("docs/superpowers/specs/2026-04-19-generator-ui-audit-data.yml")

module GeneratorUiAudit
  module_function

  GAP_TYPES = %i[
    action_key_mismatch
    computed_field_exposed
    extra_ui_field
    missing_enum_option
    missing_builder_action
    missing_field
    missing_registration
    missing_schema
    mismatched_visibility_or_default
  ].freeze

  CATEGORY_TO_PHASE = {
    "background"         => "background",
    "caching"            => "caching",
    "communication"      => "communication",
    "concurrency"        => "concurrency",
    "data_operations"    => "data",
    "file_operations"    => "file",
    "model_operations"   => "model",
    "outcome"            => "outcome",
    "payments"           => "payments",
    "realtime"           => "realtime",
    "resilience"         => "resilience",
    "response"           => "response",
    "scheduling_time"    => "scheduling",
    "security"           => "security",
    "service_invocation" => "service",
    "utility"            => "utility",
    "validation"         => "validation",
    "workflow"           => "workflow",
    "finance"            => "finance"
  }.freeze

  COMMON_STEP_FIELDS = %w[
    retryCount retryBackoff timeout guardCondition errorStrategy
  ].freeze

  COMPUTED_FIELDS = {
    "decision" => %w[_connection_match_values _route_index]
  }.freeze
  COMMON_PRESENTATION_FIELDS = %w[label description].freeze
  ELEMENT_PRESENTATION_FIELDS = {
    "decision" => %w[branches]
  }.freeze

  def run_report
    ui = load_ui_schemas
    builder_action_keys = load_builder_action_keys
    entries = build_report(ui, builder_action_keys: builder_action_keys)
    defects = entries.flat_map do |entry|
      entry.fetch(:gaps).map { |gap| gap.merge(ui_key: entry.fetch(:ui_key), phase: entry.fetch(:phase)) }
    end
    defects.concat(missing_registration_defects(builder_action_keys))
    {
      entries: entries,
      defects: defects
    }
  end

  def missing_registration_defects(ui_keys, registry: CodeGenerators::GeneratorRegistry.instance)
    action_names = registry.step_action_generators.keys.map(&:to_s).to_set

    (ui_keys.map(&:to_s).to_set - action_names).sort.map do |ui_key|
      { type: :missing_registration, ui_key: ui_key, phase: "unregistered" }
    end
  end

  def run
    report = run_report
    entries = report.fetch(:entries)
    defects = report.fetch(:defects)
    File.write(OUTPUT_PATH, entries.to_yaml)
    actionable = defects.reject { |d| d[:type] == :action_key_mismatch }.size
    puts "Wrote #{entries.size} generator audit entries to #{OUTPUT_PATH}"
    puts "Total defects: #{defects.size} (actionable: #{actionable})"
  end

  # Element types and step actions come from each generator's declared
  # config_schema. Returns a Hash keyed by ui_key. Each value is an Array of
  # field Hashes with symbol keys — :key, :type, :required, :default, :options,
  # :visibleWhen (where present).
  def load_ui_schemas
    elements = CodeGenerators::Shared::SchemaReader::ELEMENT_TYPE_KEYS.index_with do |key|
      CodeGenerators::Shared::SchemaReader.read(key)
    end
    actions = CodeGenerators::GeneratorRegistry.step_action_generators.values.uniq.each_with_object({}) do |klass, acc|
      acc[klass.generator_name] = CodeGenerators::Shared::SchemaReader.read(klass.generator_name)
    end
    elements.merge(actions)
  end

  def load_builder_action_keys
    CodeGenerators::GeneratorRegistry.step_action_generators.keys.map(&:to_s).uniq.sort
  end

  # Returns an Array of Hashes describing every in-scope generator:
  #   { generator_key:, ui_key:, kind:, phase:, generator_path:, ui_ref: }
  def discover_generators(ui_keys = nil)
    registry = CodeGenerators::GeneratorRegistry.instance
    ui_keys = ui_keys&.map(&:to_s)&.to_set

    element_types = registry_entries(
      registry.element_type_generators,
      kind: :element_type,
      ui_keys: ui_keys
    )
    step_actions = registry_entries(
      registry.step_action_generators,
      kind: :step_action,
      ui_keys: ui_keys
    )

    element_types + step_actions
  end

  def registry_entries(registrations, kind:, ui_keys:)
    registrations.group_by { |_name, klass| klass }.map do |klass, pairs|
      registered_names = pairs.map(&:first)
      generator_key = klass.generator_name
      ui_key = registered_names.find { |name| ui_keys&.include?(name) } || generator_key
      generator_path = relative_generator_path(klass)
      phase =
        if kind == :element_type
          "element_#{generator_key}"
        else
          category = Pathname.new(generator_path).each_filename.to_a[-2]
          CATEGORY_TO_PHASE.fetch(category)
        end

      {
        generator: klass.name,
        generator_key: generator_key,
        registered_names: registered_names,
        ui_key: ui_key,
        kind: kind,
        phase: phase,
        generator_path: generator_path,
        ui_ref: "config_schema.rb::#{ui_key}"
      }
    end.sort_by { |entry| entry.fetch(:generator_path) }
  end

  def relative_generator_path(klass)
    source_path = klass.instance_method(:generate_body).source_location&.first
    raise "No generate_body source path for #{klass.name}" unless source_path

    Pathname.new(source_path).relative_path_from(Rails.root).to_s
  end

  # --- Contract extraction ----------------------------------------------

  CONFIG_ACCESS_RE = /config\[(?<q>['"])(?<key>[A-Za-z_][A-Za-z0-9_]*)\k<q>\]/.freeze
  CFG_ACCESS_RE    = /\bcfg\[(?<q>['"])(?<key>[A-Za-z_][A-Za-z0-9_]*)\k<q>\]/.freeze
  FETCH_ENUM_RE    = /fetch_enum\(\s*['"](?<key>[A-Za-z_][A-Za-z0-9_]*)['"]\s*,\s*(?<vals>[A-Z_]+|%w\[[^\]]*\]|\[[^\]]*\])/.freeze
  # `expression_config` / `ident_config` / `fetch_ident` are the hardened config
  # readers (Shared::ExpressionSafety, Shared::IdentifierSanitizer,
  # Shared::ConfigFieldReader). They read a config key just like config["..."],
  # so they must be listed here or the key becomes invisible to this audit.
  FETCH_HELPER_RE  = /(?:fetch_(?:with_default|int_positive|ident)|expression_config|ident_config)\(\s*['"](?<key>[A-Za-z_][A-Za-z0-9_]*)['"]/.freeze
  CONST_ASSIGN_RE  = /^\s+(?<name>[A-Z][A-Z_0-9]*)\s*=\s*%w\[(?<body>[^\]]*)\]\.freeze/.freeze
  CASE_BLOCK_RE    = /case\s+(?<scrutinee>[^\n]+?)\s*\n(?<body>.*?)\n\s*end/m.freeze

  # Extracts the config contract for one generator file.
  PORTED_ROLE_TYPE = {
    enum: :enum,
    flag: :boolean,
    integer: :integer,
    decimal: :number,
    mapping: :key_value_list,
    list: :list,
    conditions: :conditions,
    template: :textarea,
    expression: :expression
  }.freeze

  def extract_contract(path, generator_class: nil)
    source_path = Pathname.new(path)
    source_path = Rails.root.join(source_path) unless source_path.absolute?
    source = File.read(source_path)
    generator_class ||= constantize_generator(source_path)

    keys_read = Set.new
    enums     = Hash.new { |h, k| h[k] = Set.new }
    required  = Set.new
    fields    = {}

    # 1. Direct config["..."] / cfg["..."] accesses.
    source.scan(CONFIG_ACCESS_RE) { keys_read << Regexp.last_match[:key] }
    source.scan(CFG_ACCESS_RE)    { keys_read << Regexp.last_match[:key] }

    # 2. fetch_enum / fetch_with_default / fetch_int_positive
    source.scan(FETCH_ENUM_RE) do
      m = Regexp.last_match
      keys_read << m[:key]
      vals_expr = m[:vals]
      if vals_expr.start_with?("%w[")
        inner = vals_expr.sub(/\A%w\[/, "").sub(/\]\z/, "")
        inner.split(/\s+/).reject(&:empty?).each { |v| enums[m[:key]] << v }
      end
    end
    source.scan(FETCH_HELPER_RE) { keys_read << Regexp.last_match[:key] }

    # 3. Constants (VALUE_TYPES = %w[...])
    constants = {}
    source.scan(CONST_ASSIGN_RE) do
      m = Regexp.last_match
      constants[m[:name]] = m[:body].split(/\s+/).reject(&:empty?)
    end

    # Attach constant-backed enums via `fetch_enum("key", CONST_NAME, ...)`
    source.scan(/fetch_enum\(\s*['"](?<key>[A-Za-z_0-9]+)['"]\s*,\s*(?<const>[A-Z][A-Z_0-9]*)/) do
      m = Regexp.last_match
      constants[m[:const]]&.each { |v| enums[m[:key]] << v }
    end

    # 4. case / when blocks.
    local_to_config_key = {}
    source.scan(/^\s*([a-z_][a-z_0-9]*)\s*=\s*config\[['"]([A-Za-z_0-9]+)['"]\]/) do
      local, cfg_key = $1, $2
      local_to_config_key[local] = cfg_key
    end

    source.scan(CASE_BLOCK_RE) do
      m = Regexp.last_match
      scrutinee = m[:scrutinee].strip
      body      = m[:body]
      key =
        if scrutinee =~ /\Aconfig\[['"]([^'"]+)['"]\]\z/
          Regexp.last_match(1)
        elsif scrutinee =~ /\Acfg\[['"]([^'"]+)['"]\]\z/
          Regexp.last_match(1)
        elsif local_to_config_key.key?(scrutinee)
          local_to_config_key[scrutinee]
        end
      next unless key

      keys_read << key
      body.scan(/^\s*when\s+['"]([^'"]+)['"]/).flatten.each { |v| enums[key] << v }
    end

    # 5. Required keys (validate_config / validate blocks): blank/empty checks
    blank_check = /cfg\[['"]([A-Za-z_0-9]+)['"]\]\.(?:blank\?|to_s\.strip\.empty\?|nil\?|empty\?)/
    source.each_line do |line|
      next unless (m = line.match(blank_check))
      next if line =~ /\bunless\b/ || line.include?("&&") || line.include?("||")

      required << m[1]
    end

    # 6. Declarative config_schema field declarations
    source.scan(
      /^\s*field\s+:(?<key>[A-Za-z_0-9]+)(?:\s*,\s*:(?<type>[a-z_]+))?(?<rest>[^\n]*)$/
    ) do
      m = Regexp.last_match
      key  = m[:key]
      type = (m[:type] || "string").to_sym
      rest = m[:rest]
      metadata = { type: type, required: rest.match?(/required:\s*true/) }

      keys_read << key
      required << key if metadata[:required]

      if type == :boolean
        %w[true false].each { |v| enums[key] << v }
      elsif (vals = rest[/values:\s*(%w\[[^\]]*\]|[A-Z][A-Z_0-9]*)/, 1])
        values = if vals.start_with?("%w[")
          vals.sub(/\A%w\[/, "").sub(/\]\z/, "").split(/\s+/).reject(&:empty?)
        else
          constants.fetch(vals, [])
        end
        metadata[:values] = values
        values.each { |v| enums[key] << v }
      end

      default = extract_literal_keyword(rest, "default")
      metadata[:default] = default[:value] if default[:found]
      fields[key] = metadata
    end

    runtime_fields(generator_class).each do |key, metadata|
      fields[key] = fields.fetch(key, {}).merge(metadata)
      keys_read << key
      required << key if metadata[:required]
      values = metadata[:type] == :boolean ? %w[true false] : Array(metadata[:values])
      values.each { |value| enums[key] << value.to_s }
    end

    {
      keys_read: keys_read.to_a,
      enums: enums.transform_values(&:to_a),
      required: required.to_a,
      fields: fields
    }
  end

  def constantize_generator(path)
    relative = Pathname.new(path)
    relative = relative.relative_path_from(Rails.root) if relative.absolute?
    relative.to_s.delete_prefix("app/services/").delete_suffix(".rb").camelize.safe_constantize
  rescue ArgumentError
    nil
  end

  def runtime_fields(generator_class)
    return {} unless generator_class&.respond_to?(:config_fields)

    generator_class.config_fields.each_with_object({}) do |entry, fields|
      metadata = entry.transform_keys(&:to_sym)
      opts = metadata[:options].is_a?(Hash) ? metadata[:options].symbolize_keys : {}
      name = (metadata.delete(:name) || metadata[:key]).to_s
      role = (metadata[:role] || opts[:role])&.to_sym
      type = (metadata[:type] || PORTED_ROLE_TYPE[role] || :string).to_sym
      metadata[:type] = type
      metadata[:required] = metadata.fetch(:required) { opts[:required] }
      metadata[:default] = metadata.key?(:default) ? metadata[:default] : opts[:default]
      if type == :boolean
        metadata[:values] = %w[true false]
      elsif metadata.key?(:values)
        metadata[:values] = Array(metadata[:values]).dup
      elsif opts.key?(:values)
        metadata[:values] = Array(opts[:values]).dup
      end
      fields[name] = metadata.compact
    end
  end

  def extract_literal_keyword(source, keyword)
    raw = source[
      /\b#{Regexp.escape(keyword)}:\s*(?<value>"(?:\\.|[^"])*"|'(?:\\.|[^'])*'|\{\s*\}|\[\s*\]|-?\d+(?:\.\d+)?|true|false|nil|:[a-z_][a-z_0-9]*)/,
      :value
    ]
    return { found: false } unless raw

    value =
      case raw
      when "true" then true
      when "false" then false
      when "nil" then nil
      when /\A\{\s*\}\z/ then {}
      when /\A\[\s*\]\z/ then []
      when /\A-?\d+\z/ then raw.to_i
      when /\A-?\d+\.\d+\z/ then raw.to_f
      when /\A:/ then raw.delete_prefix(":").to_sym
      else
        raw[1...-1].gsub(/\\(['"\\])/, '\1')
      end
    { found: true, value: value }
  end

  # --- Gap computation --------------------------------------------------

  CROSS_CUTTING_KEYS = COMMON_STEP_FIELDS

  def suggested_input_type(key)
    case key
    when /Expression\z/, /Template\z/, /Body\z/, /Script\z/, "customExpression"
      :textarea
    when /Count\z/, /Length\z/, /Size\z/, /Width\z/, /Seconds\z/, /Depth\z/,
         /Precision\z/, /Amount\z/, /Offset\z/, /Limit\z/, /Port\z/, /Ttl\z/,
         /Timeout\z/, /MaxWait\z/, /MinWait\z/, /Interval\z/
      :number
    when /\AarrayValue\z/, /\AhashValue\z/,
         /List\z/, /Fields\z/, /Mappings\z/, /Mapping\z/, /Tags\z/,
         /Operations\z/, /Headers\z/, /Interpolations\z/, /Params\z/,
         /Values\z/, /Pairs\z/, /Patterns\z/
      :key_value_list
    else
      :text
    end
  end

  def suggested_label(key)
    key.gsub(/([A-Z])/, ' \1').strip.split(/\s+/).map(&:capitalize).join(" ")
  end

  # Returns an Array of gap Hashes for one generator contract vs. its UI schema.
  def compute_gaps(contract, ui_fields, generator_key = nil, kind: nil, builder_action_present: true)
    return [{ type: :missing_schema }] if kind == :element_type && ui_fields.nil?

    ui_fields ||= []
    ui_by_key = ui_fields.to_h { |f| [f[:key].to_s, f] }
    gaps = []

    gaps << { type: :missing_builder_action } if kind == :step_action && !builder_action_present

    COMPUTED_FIELDS.fetch(generator_key, []).each do |key|
      gaps << { type: :computed_field_exposed, field: key } if ui_by_key.key?(key)
    end

    # missing_enum_option
    contract[:enums].each do |key, values|
      next if values.empty?
      ui_field = ui_by_key[key]
      next unless ui_field && ui_field[:type].to_sym == :select
      ui_values = (ui_field[:options] || []).map { |o| o["value"] || o[:value] }.map(&:to_s)
      missing = values.map(&:to_s) - ui_values
      gaps << {
        type: :missing_enum_option,
        field: key,
        missing: missing.sort
      } if missing.any?
    end

    # missing_field
    contract[:keys_read].each do |key|
      next if ui_by_key.key?(key)
      next if CROSS_CUTTING_KEYS.include?(key) || COMMON_STEP_FIELDS.include?(key)
      next if generator_key && COMPUTED_FIELDS.fetch(generator_key, []).include?(key)

      input_type = suggested_input_type(key)
      fix = {
        key: key,
        type: input_type,
        label: suggested_label(key)
      }
      anchor = detect_visibility_anchor(contract, key)
      fix[:visibleWhen] = { field: anchor[:field], value: anchor[:value] } if anchor
      gaps << { type: :missing_field, field: key, suggested: fix }
    end

    # mismatched_visibility_or_default: required keys missing required: true
    contract[:required].each do |key|
      ui_field = ui_by_key[key]
      next unless ui_field
      unless ui_field[:required] == true
        gaps << {
          type: :mismatched_visibility_or_default,
          field: key,
          fix: { set: { required: true } }
        }
      end
    end

    contract.fetch(:fields, {}).each do |key, metadata|
      next unless metadata.key?(:default)

      ui_field = ui_by_key[key]
      next unless ui_field
      next if matching_default?(ui_field, metadata)

      gaps << {
        type: :mismatched_visibility_or_default,
        field: key,
        fix: { set: { default: metadata[:default] } }
      }
    end

    if kind == :element_type
      ui_by_key.each_key do |key|
        next if contract[:keys_read].include?(key)
        next if COMMON_PRESENTATION_FIELDS.include?(key)
        next if ELEMENT_PRESENTATION_FIELDS.fetch(generator_key, []).include?(key)
        next if COMPUTED_FIELDS.fetch(generator_key, []).include?(key)

        gaps << { type: :extra_ui_field, field: key }
      end
    end

    gaps
  end

  # Compare serialized defaults, not textarea display values. The opted-in
  # JSON/expression editor pretty-prints objects, parses object text, preserves
  # expressions/malformed input, and omits blank optional fields. Omission lets
  # the generator's declared default apply; it is not an explicit empty string.
  def matching_default?(ui_field, metadata)
    value = ui_field[:default]
    return value == metadata[:default] unless ui_field[:type]&.to_sym == :json_or_expression

    if !ui_field.key?(:default) || value.nil?
      return ui_field[:required] != true && metadata[:required] != true
    end

    # JS renders any object (including an array) as JSON, but only object text
    # starting with '{' is parsed on save. Arrays therefore remain strings.
    text = value.is_a?(Hash) || value.is_a?(Array) ? JSON.generate(value) : value.to_s.strip
    serialized = text
    if text.start_with?("{")
      begin
        serialized = JSON.parse(text)
      rescue JSON::ParserError
        # The editor keeps malformed JSON verbatim for server validation.
      end
    end
    serialized == metadata[:default]
  end

  def detect_visibility_anchor(_contract, _key)
    nil
  end

  # Assemble the full audit report.
  def build_report(ui, builder_action_keys: load_builder_action_keys)
    builder_action_keys = builder_action_keys.map(&:to_s).to_set

    discover_generators(ui.keys).map do |g|
      generator_class = g.fetch(:generator).constantize
      contract = extract_contract(g[:generator_path], generator_class: generator_class)
      ui_fields = ui[g[:ui_key]]
      gaps = compute_gaps(
        contract,
        ui_fields,
        g[:generator_key],
        kind: g[:kind],
        builder_action_present: g[:kind] != :step_action || builder_action_keys.include?(g[:ui_key])
      )

      if g[:ui_key] != g[:generator_key] && !g[:registered_names].include?(g[:ui_key])
        gaps = [{ type: :action_key_mismatch, ui_key: g[:ui_key] }] + gaps
      end

      {
        generator: g[:generator],
        generator_key: g[:generator_key],
        registered_names: g[:registered_names],
        ui_key: g[:ui_key],
        kind: g[:kind],
        phase: g[:phase],
        ui_ref: g[:ui_ref],
        generator_path: g[:generator_path],
        contract: {
          keys_read: contract[:keys_read].sort,
          enums:     contract[:enums].transform_values(&:sort),
          required:  contract[:required].sort,
          fields:    contract[:fields].sort.to_h
        },
        gaps: gaps
      }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  report = GeneratorUiAudit.run_report
  File.write(OUTPUT_PATH, report.fetch(:entries).to_yaml)
  puts "Wrote #{report.fetch(:entries).size} generator audit entries to #{OUTPUT_PATH}"
  puts "Total defects: #{report.fetch(:defects).size}"
  abort "Generator/UI defects: #{report.fetch(:defects).size}" if report.fetch(:defects).any?
end
