# frozen_string_literal: true

require "digest"
require "ripper"
require Rails.root.join("spec/support/generator_conformance/inert_field_allowlist").to_s

# Semantic conformance harness for flowchart code generators.
#
# The repository's structural audits prove that a property-editor field is
# *referenced* by a generator. They cannot prove the field *changes the emitted
# source*. This harness closes that gap by emitting source twice — once at a
# baseline config, once with a single field perturbed — and comparing.
module GeneratorConformance
  class Error < StandardError; end

  # These orchestration nodes deliberately have no standalone step method.
  SOURCELESS_GENERATORS = %w[
    CodeGenerators::ElementTypes::Start::StartGenerator
    CodeGenerators::ElementTypes::Subflow::SubflowGenerator
  ].freeze

  # Field types the harness cannot meaningfully perturb. `steps` and `branches`
  # are nested structural editors owned by the element-type track; `condition`
  # carries a builder-specific shape probed by its own track.
  UNPROBEABLE_TYPES = %i[steps branches condition].freeze

  # Samples select one mode. Supply valid dependent configuration so fields that
  # are only valid with extra required values are compiled/probed, not merely
  # rejected because the sample is incomplete.
  BASELINE_CONFIG_OVERRIDES = {
    "send_sms" => {
      "templateKey" => "verify_code",
      "vars" => [{ "key" => "code", "value" => "ctx.code" }],
      "idempotencyKey" => "ctx.request_key"
    },
    "query_models" => { "pageSize" => 20 },
    "filter_collection" => { "returns" => "first" },
    "send_webhook" => { "secretExpression" => '"webhook-secret"' },
    "cache_read" => { "onMiss" => "default", "defaultValue" => "{}" },
    "format_value" => { "formatType" => "date", "dateStyle" => "custom", "customFormat" => "%Y-%m-%d" },
    "enqueue_job" => { "cronExpression" => "" }
  }.freeze

  module_function

  # Disk discovery is deliberately independent of GeneratorRegistry's allowlist:
  # an implementation accidentally omitted by the registry must still be counted.
  def inventory
    Rails.root.glob("app/services/code_generators/element_types/**/*_generator.rb").sort.map do |path|
      relative = path.relative_path_from(Rails.root).to_s
      klass = relative.delete_prefix("app/services/").delete_suffix(".rb").camelize.constantize
      {
        generator: klass,
        implementation: relative,
        spec: relative.sub("app/", "spec/").sub(/\.rb\z/, "_spec.rb")
      }
    end
  end

  # Parse executable RSpec declarations, not mentions in comments or strings.
  # Dedicated specs use `RSpec.describe Fully::Qualified::Generator do`.
  def dedicated_spec_identities(source)
    tree = Ripper.sexp(source)
    raise Error, "Dedicated spec does not parse" unless tree

    identities = []
    visit = lambda do |node|
      next unless node.is_a?(Array)

      if node[0] == :command_call && node.dig(1, 1, 1) == "RSpec" && node.dig(3, 1) == "describe"
        identities << constant_identity(node.dig(4, 1, 0))
      end
      node.each { |child| visit.call(child) if child.is_a?(Array) }
    end
    visit.call(tree)
    identities.compact
  end

  def constant_identity(node)
    return unless node.is_a?(Array)

    case node[0]
    when :var_ref, :const_ref
      node.dig(1, 1) if node.dig(1, 0) == :@const
    when :const_path_ref
      [constant_identity(node[1]), node.dig(2, 1)].compact.join("::")
    end
  end

  # Property-editor fields for an action or element type from the Ruby schema.
  def ui_fields(key)
    CodeGenerators::Shared::SchemaReader.read(key)
  end

  # Never turn an exception into comparable source: a crash is not a delta.
  def emit(generator_class, config)
    compiled_result(generator_class, config).fetch(:body)
  end

  def validation_errors(generator_class, config)
    element = { "config" => config, "properties" => config, "label" => "test_step" }
    errors = generator_class.new(element, {}).validate_config(config)
    raise Error, "#{generator_class.name}: validation_errors must be an Array" unless errors.is_a?(Array)

    errors
  end

  def compiled_result(generator_class, config, context: {})
    result = CodeGenerators::TestRunner.run(generator_class, config: config, context: context)
    errors = result.fetch(:validation_errors)
    raise Error, "#{generator_class.name}: validation_errors must be an Array" unless errors.is_a?(Array)
    raise Error, "#{generator_class.name}: rejected config: #{errors.join('; ')}" if errors.any?

    code = result.fetch(:code)
    body = result.fetch(:body)
    if SOURCELESS_GENERATORS.include?(generator_class.name)
      raise Error, "#{generator_class.name}: unexpected standalone source" unless body.nil? && code.nil?
    else
      unless body.is_a?(String) && !body.strip.empty? && code.is_a?(String) && !code.strip.empty?
        raise Error, "#{generator_class.name}: missing generated source"
      end
      RubyVM::InstructionSequence.compile(code)
    end
    result
  end

  # A value guaranteed to differ from +baseline+, or nil when the field type
  # cannot be probed.
  def probe_value(field, baseline)
    type = field[:type]&.to_sym
    return nil if UNPROBEABLE_TYPES.include?(type)

    case type
    when :select
      values = Array(field[:options]).map { |o| o["value"] || o[:value] }.compact.map(&:to_s)
      values.find { |v| v != baseline.to_s }
    when :number
      n = baseline.to_i + 7
      max = field[:max]
      n = max.to_i if max && n > max.to_i
      n
    when :key_value_list
      [{ "key" => "conformance_probe_tag", "value" => "probe" }]
    when :list
      ["conformance_probe_#{field[:key]}"]
    when :checkbox
      baseline == true ? false : true
    when :json_or_expression
      baseline.is_a?(Hash) ? "ctx.conformance_probe_#{field[:key]}" : { "conformance_probe_tag" => "probe" }
    when :text, :textarea
      "conformance_probe_#{field[:key]}"
    when :conditions
      [{ "field" => "status", "operator" => "eq", "value" => "conformance_probe" }]
    else
      raise Error, "No conformance probe for #{field[:key]} (#{type.inspect})"
    end
  end

  # Baseline config for a generator: an example value for every declared field,
  # hidden ones included, so flipping a mode switch keeps the config complete.
  def baseline_config(generator_class)
    examples = generator_class._config_schema&.examples || generator_class.sample_input || {}
    examples.merge(BASELINE_CONFIG_OVERRIDES.fetch(generator_class.generator_name, {}))
  end

  # A value for the anchor field that makes +field+ visible in the property
  # editor, or nil when the field is unconditional.
  def shown_anchor_value(field)
    condition = field[:visibleWhen]
    return nil if condition.nil?

    anchor = (condition["field"] || condition[:field]).to_s
    shown = Array(condition["values"] || condition[:values] ||
                  condition["value"]  || condition[:value]).map(&:to_s)
    return nil if anchor.empty? || shown.empty?

    [anchor, shown.first]
  end

  # Baseline config with any visibleWhen condition satisfied, so a conditional
  # field is probed under the configuration that actually exposes it. Without
  # this, a field like hash_data.cost (visible only when algorithm == "bcrypt")
  # is probed against a sha256 sample and looks inert when it is not.
  def visible_baseline(generator_class, field)
    baseline = baseline_config(generator_class)
    key = field[:key].to_s
    schema = generator_class.respond_to?(:_config_schema) ? generator_class._config_schema : nil
    declared = Array(schema&.fields).find { |item| item.respond_to?(:name) && item.name == key }

    Array(declared&.conditions).each do |cond|
      when_hash = cond.is_a?(Hash) ? cond[:when] : nil
      next unless when_hash.is_a?(Hash)

      when_hash.each do |name, values|
        allowed = Array(values).map(&:to_s)
        next if allowed.include?(baseline[name.to_s].to_s)

        baseline = baseline.merge(name.to_s => allowed.first)
      end
    end

    caps = Array(declared&.capabilities).map(&:to_s)
    baseline = baseline.merge("circuitBreaker" => true) if caps.include?("circuit_breaker") && key != "circuitBreaker"
    baseline = baseline.merge("retryOnTransportError" => true) if caps.include?("transport_retry") && key == "retryAttempts"

    anchor_pair = shown_anchor_value(field)
    return baseline if anchor_pair.nil?

    baseline.merge(anchor_pair[0] => anchor_pair[1])
  end

  # Classify one field:
  #   :changed  — perturbing the field changed emitted source (correct)
  #   :inert    — emitted source was byte-identical (defect unless allow-listed)
  #   :rejected — the probe was refused by server-side validation (acceptable;
  #               the generator validates rather than silently ignoring)
  #   :validation_changed — setting the field made an invalid baseline valid;
  #               compile the accepted variant, but do not claim a source delta
  #   :skipped  — the field type is not probeable
  def field_delta(generator_class, _action_key, field)
    key = field[:key].to_s
    baseline = visible_baseline(generator_class, field)
    probe = probe_value(field, baseline[key])
    return :skipped if probe.nil?

    variant = baseline.merge(key => probe)
    return :rejected if validation_errors(generator_class, variant).any?
    if validation_errors(generator_class, baseline).any?
      emit(generator_class, variant)
      return :validation_changed
    end

    emit(generator_class, baseline) == emit(generator_class, variant) ? :inert : :changed
  end

  # Digest of emitted source per enum option. Raises when an option emits
  # source that does not compile.
  def enum_coverage(generator_class, _action_key, field)
    key = field[:key].to_s
    baseline = visible_baseline(generator_class, field)
    options = Array(field[:options]).map { |o| o["value"] || o[:value] }.compact.map(&:to_s)

    options.each_with_object({}) do |option, acc|
      config = baseline.merge(key => option)
      next if validation_errors(generator_class, config).any?

      acc[option] = Digest::SHA256.hexdigest(emit(generator_class, config).to_s)
    end
  end

  # Enum options that emit byte-identical source.
  #
  # `enum_coverage` records one digest per option but nothing forces those
  # digests apart; a select can therefore offer N options while the generator
  # implements fewer than N behaviors. That is exactly the property-editor/
  # generator gap this harness exists to close, so it is surfaced separately.
  #
  # Options the generator REFUSES under the visible baseline are excluded: a
  # rejected option emits no meaningful body, and `field_delta` already treats
  # server-side rejection as the correct alternative to silent acceptance.
  #
  # @return [Array<Array<String>>] groups of >= 2 option values sharing a digest
  def duplicate_enum_options(generator_class, action_key, field)
    key = field[:key].to_s
    baseline = visible_baseline(generator_class, field)
    options = Array(field[:options]).map { |o| o["value"] || o[:value] }.compact.map(&:to_s)

    digests = options.each_with_object({}) do |option, acc|
      config = baseline.merge(key => option)
      next if validation_errors(generator_class, config).any?

      body = emit(generator_class, config)
      acc[option] = Digest::SHA256.hexdigest(body.to_s)
    end

    digests.group_by { |_option, digest| digest }
           .values
           .map { |pairs| pairs.map(&:first) }
           .select { |group| group.size > 1 }
  end

  def duplicate_enum_allow_listed?(action_key, field_key, group)
    entry = DUPLICATE_ENUM_OPTION_ALLOWLIST.dig(action_key.to_s, field_key.to_s)
    return false if entry.nil?

    Array(entry[:options]).map(&:to_s).sort == group.map(&:to_s).sort
  end

  # Config keys a generator never references anywhere in its own source or the
  # mixins it includes — a `dead_ui_field`. The dynamic probes above catch a
  # field that is read but ignored; they CANNOT catch a field whose probe is
  # rejected by validation or skipped as unprobeable, because neither outcome
  # produces a body difference to compare. A structurally dead field can hide
  # in exactly that shadow, so it is checked statically as well.
  def dead_ui_fields(generator_class, action_key)
    source = generator_reference_source(generator_class)
    return [] if source.nil?

    ui_fields(action_key).map { |f| f[:key].to_s }.reject do |key|
      source.match?(/['":]#{Regexp.escape(key)}['"]?/)
    end
  end

  # A generator's own source plus every mixin it includes, transitively, with
  # `self.sample_input` stripped — a key mentioned only there is documentation,
  # not a read. Mirrors scripts/audit_step_action_config.rb.
  def generator_reference_source(generator_class, seen = Set.new)
    path = Object.const_source_location(generator_class.name)&.first
    return nil if path.nil? || !File.exist?(path) || !seen.add?(path)

    source = File.read(path)
    parts = [source.sub(/def self\.sample_input.*?\n\s+end\n/m, "")]
    generator_class.included_modules.each do |mod|
      next if mod.name.nil? || !mod.name.start_with?("CodeGenerators")

      included = generator_reference_source(mod, seen)
      parts << included unless included.nil?
    end
    parts.join("\n")
  end

  # True when a field whose visibleWhen condition is UNMET still changes the
  # emitted source. The property editor hides such a field, so a user cannot
  # see or control the behavior it drives.
  def visibility_leak?(generator_class, action_key, field)
    condition = field[:visibleWhen]
    return false if condition.nil?

    anchor = (condition["field"] || condition[:field]).to_s
    shown = Array(condition["values"] || condition[:values] ||
                  condition["value"]  || condition[:value]).map(&:to_s)

    anchor_field = ui_fields(action_key).find { |f| f[:key].to_s == anchor }
    return false if anchor_field.nil?

    anchor_options = Array(anchor_field[:options])
                     .map { |o| (o["value"] || o[:value]).to_s }
    hidden_anchors = anchor_options.reject { |v| shown.include?(v) }
    return false if hidden_anchors.empty?

    key = field[:key].to_s
    probe = probe_value(field, nil)
    return false if probe.nil?

    hidden_baseline = hidden_anchors.lazy.map do |value|
      config = baseline_config(generator_class).merge(anchor => value).except(key)
      # Drop sibling fields hidden by the same mode switch. Keeping, for example,
      # SVG-only includeText=true makes every raster textFont baseline invalid.
      ui_fields(action_key).each do |sibling|
        rule = sibling[:visibleWhen]
        next unless rule

        controller = (rule["field"] || rule[:field]).to_s
        values = Array(rule["values"] || rule[:values] || rule["value"] || rule[:value]).map(&:to_s)
        config.delete(sibling[:key].to_s) unless values.include?(config[controller].to_s)
      end
      config
    end.find { |config| validation_errors(generator_class, config).empty? }
    raise Error, "#{action_key}.#{key}: no valid hidden baseline" unless hidden_baseline

    with_hidden_field = hidden_baseline.merge(key => probe)
    return :rejected if validation_errors(generator_class, with_hidden_field).any?

    emit(generator_class, hidden_baseline) != emit(generator_class, with_hidden_field)
  end

  def allow_listed?(action_key, field_key)
    INERT_FIELD_ALLOWLIST.fetch(action_key.to_s, {}).key?(field_key.to_s)
  end
end
