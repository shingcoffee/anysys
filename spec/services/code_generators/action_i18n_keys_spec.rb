# frozen_string_literal: true

require "rails_helper"

# G3: every key a ported step action needs (Phase 3 spec A3) exists in each
# locale on its own (no fallbacks), with identical %{} variables in en and
# zh-CN. Key paths mirror ActionCatalog, ActionCatalog::FieldPresenter,
# ConfigSchema#message_for and FlowchartRuntime::Step.fail.
RSpec.describe "step-action i18n keys" do
  locales = %w[en zh-CN]
  root = Rails.root

  runtime_dir = root.join("app/services/flowchart_runtime")
  generator_dir = root.join("app/services/code_generators/element_types")

  code_literal = /(?::"(?<code>[a-z0-9_.\#{}()\[\]:\s]+)"|:(?<code>[a-z0-9_]+)|'"(?<code>[a-z0-9_.]+)"')/
  emitter_call = /(?<![.\w])(?:fail_with|attempt)\(\s*/
  step_call = /Step\.(?:fail|attempt)\(\s*ctx,\s*/
  errors_add = /errors\.add\(\s*[^,()]+,\s*:(?<code>[a-z0-9_]+)/

  # Runtime codes built by interpolation, expanded from the source that
  # produces their suffix.
  dynamic_runtime_codes = {
    'send_sms.#{template_vars_code(error)}' => lambda {
      source = runtime_dir.join("sms_delivery.rb").read
      method = source[/def template_vars_code.*?\n    end/m]
      method.scan(/:([a-z_]+)/).flatten.map { |suffix| "send_sms.#{suffix}" }
    },
    'refund_payment.#{error.code}' => lambda {
      source = root.join("app/services/payments/activities/refund.rb").read
      source.scan(/code: :([a-z_]+)/).flatten.map { |suffix| "refund_payment.#{suffix}" }
    },
    'next_occurrence.#{result[:error]}' => lambda {
      runtime_dir.join("recurrence.rb").read.scan(/error: :([a-z_]+)/).flatten.uniq.map { |error| "next_occurrence.#{error}" }
    },
    'validate_value.#{rule}' => lambda {
      FlowchartRuntime::ValueValidator::RULES.map { |rule| "validate_value.#{rule}" }
    }
  }

  define_method(:locales) { locales }

  define_method(:generators) do
    CodeGenerators::GeneratorRegistry.step_action_generators.values.uniq.sort_by(&:generator_name)
  end

  helper_files = Dir[generator_dir.join("**/*.rb")].reject { |path| path.end_with?("_generator.rb") }

  # The generator's own file, any module it mixes in, and any helper under
  # element_types/ it references by constant (e.g. CacheKeyGuard.validate).
  define_method(:source_files) do |generator|
    files = generator.ancestors.filter_map do |mod|
      next unless mod.name

      path = Object.const_source_location(mod.name)&.first
      path if path&.start_with?(generator_dir.to_s)
    end
    loop do
      text = files.map { |path| File.read(path) }.join("\n")
      referenced = helper_files.select { |path| text.match?(/\b#{File.basename(path, '.rb').camelize}\b/) }
      break if (referenced - files).empty?

      files |= referenced
    end
    files.uniq
  end

  define_method(:source_for) do |generator|
    source_files(generator).map { |path| File.read(path) }.join("\n")
  end

  # Codes passed to fail_with / attempt / Step.fail / Step.attempt. Calls
  # whose code is not a literal are returned as nil so the spec can reject
  # them instead of silently skipping a key.
  define_method(:emitted_codes) do |source|
    [emitter_call, step_call].flat_map do |call|
      source.to_enum(:scan, call).map do
        rest = Regexp.last_match.post_match
        match = rest.match(/\A#{code_literal}/)
        match && match[:code]
      end
    end
  end

  define_method(:runtime_codes) do
    Dir[runtime_dir.join("**/*.rb")].sort.flat_map do |path|
      next [] if path.end_with?("/step.rb")

      emitted_codes(File.read(path)).map { |code| [code, path] }
    end
  end

  define_method(:expand_runtime_code) do |code|
    return [code] unless code&.include?('#{')

    expander = dynamic_runtime_codes[code]
    expander ? expander.call : [nil]
  end

  define_method(:present?) do |key, locale|
    I18n.exists?(key, locale, fallback: false) &&
      I18n.t(key, locale: locale, fallback: false, raise: true).is_a?(String)
  end

  define_method(:resolve) do |keys, locale|
    keys.find { |key| present?(key, locale) }
  end

  define_method(:variables) do |key, locale|
    I18n.t(key, locale: locale, fallback: false, raise: true).scan(/%\{(\w+)\}/).flatten.uniq.sort
  end

  # Every lookup the catalog / validator / runtime performs, as
  # [description, [candidate keys in lookup order]].
  define_method(:required_lookups) do
    lookups = []
    categories = CodeGenerators::ActionCatalog.export(locale: "en")["categories"].map { |row| row["key"] }
    categories.each { |key| lookups << ["category #{key}", ["flowchart_actions.categories.#{key}"]] }

    any_optional_enum = false
    generators.each do |generator|
      action = generator.generator_name
      %w[label description].each do |part|
        lookups << ["#{action} #{part}", ["flowchart_actions.#{action}.#{part}"]]
      end

      generator._config_schema.fields.each do |field|
        parts = %w[label help]
        parts << "placeholder" if field.options[:placeholder]
        parts.each do |part|
          lookups << [
            "#{action}.#{field.name} #{part}",
            [
              "flowchart_actions.#{action}.fields.#{field.name}.#{part}",
              "flowchart_actions.shared.fields.#{field.name}.#{part}"
            ]
          ]
        end
        next unless field.role == :enum

        any_optional_enum ||= field.options[:required] != true
        Array(field.options[:values]).each do |value|
          option = CodeGenerators::ActionCatalog::FieldPresenter.option_key(value)
          lookups << [
            "#{action}.#{field.name} option #{value}",
            ["flowchart_actions.#{action}.fields.#{field.name}.options.#{option}"]
          ]
        end
      end

      source_for(generator).scan(errors_add).flatten.uniq.each do |code|
        lookups << [
          "#{action} config error #{code}",
          ["flowchart_actions.#{action}.errors.#{code}", "flowchart_actions.shared.errors.#{code}"]
        ]
      end
    end
    lookups << ["optional enum none", ["flowchart_actions.shared.none"]] if any_optional_enum

    schema_source = root.join("app/services/code_generators/config_schema.rb").read
    schema_source.scan(errors_add).flatten.uniq.each do |code|
      lookups << ["config_schema error #{code}", ["flowchart_actions.shared.errors.#{code}"]]
    end

    lookups.uniq
  end

  define_method(:runtime_lookups) do
    from_generators = generators.flat_map do |generator|
      emitted_codes(source_for(generator)).map { |code| [code, generator.generator_name] }
    end
    (from_generators + runtime_codes).flat_map do |code, origin|
      expand_runtime_code(code).map do |expanded|
        ["#{origin} runtime error #{expanded || code}", expanded && ["flowchart_runtime.errors.#{expanded}"]]
      end
    end.uniq
  end

  it "covers all 96 step actions" do
    expect(generators.size).to eq(96)
    expect(generators.reject(&:_config_schema).map(&:generator_name)).to eq([])
  end

  it "only emits literal (or explicitly expanded) runtime error codes" do
    unresolved = runtime_lookups.select { |_label, keys| keys.nil? }.map(&:first)
    expect(unresolved).to eq([])
  end

  locales.each do |locale|
    it "has every catalog, field, option and config-error key in #{locale} without fallbacks" do
      missing = required_lookups.reject { |_label, keys| resolve(keys, locale) }
      expect(missing.map { |label, keys| "#{label}: #{keys.join(' | ')}" }).to eq([])
    end

    it "has every runtime error code under flowchart_runtime.errors in #{locale} without fallbacks" do
      missing = runtime_lookups.select { |_label, keys| keys && !resolve(keys, locale) }
      expect(missing.map { |label, keys| "#{label}: #{keys.first}" }.uniq).to eq([])
    end
  end

  it "resolves the same key with identical %{} variables in en and zh-CN" do
    mismatches = (required_lookups + runtime_lookups.select { |_label, keys| keys }).filter_map do |label, keys|
      resolved = locales.to_h { |locale| [locale, resolve(keys, locale)] }
      next if resolved.values.any?(&:nil?)

      if resolved.values.uniq.size > 1
        "#{label}: resolves to #{resolved.inspect}"
      else
        vars = locales.to_h { |locale| [locale, variables(resolved.values.first, locale)] }
        "#{label}: #{resolved.values.first} variables #{vars.inspect}" if vars.values.uniq.size > 1
      end
    end
    expect(mismatches.uniq).to eq([])
  end
end
