#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Deep audit of every process step action's property-editor config schema
# against the Ruby generator that consumes it.
#
# Complements scripts/audit_generator_ui.rb, which only reports UI fields that
# are MISSING (generator reads a key the editor never renders). This one covers
# the opposite and subtler failure modes:
#
#   dead_ui_field        editor renders a field the generator never reads
#   reserved_key_clash   config key collides with a step-level Advanced field
#                        (retryCount / retryBackoff / timeout / guardCondition),
#                        which BaseGenerator#apply_wrappers reads off `element`
#   enum_drift           <select> offers a value the generator's allow-list rejects
#   enum_gap             allow-list accepts a value the <select> never offers
#   required_drift       generator requires a key the editor does not mark required
#
# Enum allow-lists come only from authoritative sources — a declarative
# `field :key, values: …` / `:boolean`, or a `validate` block guarding on
# `CONST.include?(cfg["key"])`. `case/when` branches are deliberately ignored:
# an `else` fallback makes them an incomplete picture of what is accepted.
#
# Usage (from repo root):
#   bundle exec ruby scripts/audit_step_action_config.rb
#
require_relative "../config/environment" if defined?(Rails) || File.exist?("config/environment.rb")
require_relative "audit_generator_ui"
require "yaml"
require "set"

AUDIT_DATA = Rails.root.join("docs/superpowers/specs/2026-04-19-generator-ui-audit-data.yml")

# Keys owned by the step card's Advanced disclosure and applied by
# BaseGenerator#apply_wrappers off `element[...]`, not `config[...]`.
# An action config schema must never redeclare these.
RESERVED_STEP_KEYS = %w[retryCount retryBackoff timeout guardCondition].freeze

module StepActionConfigAudit
  module_function

  CONST_RE     = /^\s+(?<name>[A-Z][A-Z_0-9]*)\s*=\s*%w\[(?<body>[^\]]*)\]\.freeze/.freeze
  FIELD_RE     = /^\s*field\s+:(?<key>\w+)\s*,?\s*(?::(?<type>\w+))?(?<rest>[^\n]*)$/.freeze
  GUARD_RE     = /(?<const>[A-Z][A-Z_0-9]*)\.include\?\(\s*cfg\[['"](?<key>\w+)['"]\](?:\.to_s)?\s*\)/.freeze
  FETCH_ENUM_RE = /fetch_enum\(\s*['"](?<key>\w+)['"]\s*,\s*(?<vals>[A-Z][A-Z_0-9]*|%w\[[^\]]*\])/.freeze

  def run_report
    entries = GeneratorUiAudit.run_report.fetch(:entries).select { |e| e[:kind] == :step_action }

    entries.map do |entry|
      fields = CodeGenerators::Shared::SchemaReader.read(entry[:ui_key]).map { |f| f.transform_keys(&:to_sym) }
      defects = defects_for(entry, fields)
      { ui_key: entry[:ui_key], phase: entry[:phase], defects: defects }
    end
  end

  def run
    findings = run_report.reject { |item| item[:defects].empty? }
    report(findings)
  end

  # Authoritative enum allow-lists for one generator, including the mixins it
  # includes — a shared mixin is exactly where a family of generators keeps the
  # single allow-list they must agree on (e.g. Security::KEY_SOURCES).
  def allow_lists(path)
    source = reference_source(path)
    constants = source.scan(CONST_RE).to_h { |name, body| [name, body.split(/\s+/).reject(&:empty?)] }
    lists = {}

    source.scan(FIELD_RE) do
      m = Regexp.last_match
      next unless m[:rest]

      if m[:type] == "boolean"
        lists[m[:key]] = %w[true false]
      elsif (vals = m[:rest][/values:\s*(%w\[[^\]]*\]|[A-Z][A-Z_0-9]*)/, 1])
        lists[m[:key]] = expand(vals, constants)
      end
    end

    source.scan(GUARD_RE) do
      m = Regexp.last_match
      lists[m[:key]] ||= constants[m[:const]] if constants[m[:const]]
    end

    source.scan(FETCH_ENUM_RE) do
      m = Regexp.last_match
      lists[m[:key]] ||= expand(m[:vals], constants)
    end

    lists.compact
  end

  def expand(expr, constants)
    return expr.sub(/\A%w\[/, "").sub(/\]\z/, "").split(/\s+/).reject(&:empty?) if expr.start_with?("%w[")

    constants[expr]
  end

  # Full source a generator's config keys could be referenced from: its own
  # file plus every mixin it includes, transitively.
  #
  # Two include shapes are resolved:
  #   include CodeGenerators::Shared::Foo  -> app/services/code_generators/shared/foo.rb
  #   include Foo                          -> <generator's own directory>/foo.rb
  #
  # The second shape matters: a category-local mixin (e.g. Security::KeyResolution,
  # which both encrypt_data and decrypt_data include so their key derivation
  # cannot drift apart) is where a config key is genuinely read. Without
  # following it this audit reports every such key as `dead_ui_field` even
  # though the generator honors it — and, worse, would miss a key that really
  # IS dead inside such a mixin.
  def reference_source(path, seen = Set.new)
    return "" unless path && File.exist?(path) && seen.add?(File.expand_path(path))

    source = File.read(path)
    [source, *included_mixin_paths(path, source).map { |p| reference_source(p, seen) }].join("\n")
  end

  INCLUDE_RE = /^\s*include\s+(?<name>(?:CodeGenerators::Shared::)?[A-Z]\w*)\s*$/.freeze

  def included_mixin_paths(path, source)
    dir = File.dirname(path)
    source.scan(INCLUDE_RE).flatten.uniq.map do |name|
      if name.start_with?("CodeGenerators::Shared::")
        Rails.root.join("app/services/code_generators/shared/#{name.split('::').last.underscore}.rb").to_s
      else
        File.join(dir, "#{name.underscore}.rb")
      end
    end.select { |candidate| File.exist?(candidate) }
  end

  # A key mentioned ONLY inside `self.sample_input` is documentation, not a
  # read — strip that method before looking for references.
  def strip_sample_input(source)
    source.sub(/def self\.sample_input.*?\n\s+end\n/m, "")
  end

  def defects_for(entry, fields)
    contract = entry[:contract]
    path = entry[:generator_path] || generator_path_for(entry)
    source = strip_sample_input(reference_source(path))
    by_key = fields.to_h { |f| [f[:key].to_s, f] }
    lists = allow_lists(path)
    defects = []

    fields.each do |f|
      key = f[:key].to_s
      defects << [:reserved_key_clash, key] if RESERVED_STEP_KEYS.include?(key)
      defects << [:dead_ui_field, key] unless source.match?(/['"]#{Regexp.escape(key)}['"]/)
    end

    lists.each do |key, values|
      field = by_key[key]
      next unless field && field[:type].to_s == "select"

      ui_values = (field[:options] || []).map { |o| (o["value"] || o[:value]).to_s }.reject(&:empty?)
      extra = ui_values - values
      missing = values - ui_values
      defects << [:enum_drift, "#{key}: UI offers #{extra.join('/')}; allow-list is #{values.join('/')}"] if extra.any?
      defects << [:enum_gap, "#{key}: allow-list has #{missing.join('/')} the UI never offers"] if missing.any?
    end

    contract[:required].each do |key|
      field = by_key[key]
      defects << [:required_drift, key] if field && field[:required] != true
    end

    defects
  end

  PHASE_TO_DIR = {
    "background" => "background", "caching" => "caching", "communication" => "communication",
    "concurrency" => "concurrency", "data" => "data_operations", "file" => "file_operations",
    "model" => "model_operations", "realtime" => "realtime",
    "resilience" => "resilience", "response" => "response", "scheduling" => "scheduling_time",
    "security" => "security", "service" => "service_invocation", "utility" => "utility",
    "validation" => "validation", "outcome" => "outcome", "payments" => "payments",
    "workflow" => "workflow", "finance" => "finance"
  }.freeze

  def generator_path_for(entry)
    dir = PHASE_TO_DIR.fetch(entry[:phase])
    Rails.root.join("app/services/code_generators/element_types/process/#{dir}/#{entry[:generator_key]}_generator.rb").to_s
  end

  def report(findings)
    by_type = Hash.new { |h, k| h[k] = [] }
    findings.each do |f|
      f[:defects].each { |(type, detail)| by_type[type] << "#{f[:ui_key]} (#{f[:phase]}): #{detail}" }
    end

    by_type.keys.sort.each do |type|
      puts "\n=== #{type} (#{by_type[type].size}) ==="
      by_type[type].sort.each { |line| puts "  #{line}" }
    end
    puts "\nTotal defects: #{by_type.values.sum(&:size)} across #{findings.size} actions"
  end
end

if $PROGRAM_NAME == __FILE__
  findings = StepActionConfigAudit.run_report.reject { |item| item[:defects].empty? }
  StepActionConfigAudit.report(findings)
  total_defects = findings.sum { |f| f[:defects].size }
  abort "Step action config defects: #{total_defects}" if total_defects > 0
end
