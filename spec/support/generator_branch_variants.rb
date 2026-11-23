# frozen_string_literal: true

require Rails.root.join("spec/support/generator_conformance").to_s

# Enumerates the *reachable emission branches* of a generator.
#
# Why this exists: audits that emit a generator once, at its declared
# `sample_input`, only ever inspect a single code path. A defect living in any
# other branch is invisible. This is not hypothetical — a real cross-tenant
# cache leak in `currency_convert` (an unscoped `Rails.cache.fetch("rate:...")`
# on the `rateSource == "external"` branch) survived the tenant-scoping audit
# for exactly this reason: the sample used a different rate source.
#
# Strategy: per-field variation over the baseline, one enum at a time.
# A full cross-product of every select field would be combinatorially
# explosive (several generators have 5+ enums, i.e. thousands of configs) and
# is deliberately NOT attempted. Varying one enum at a time over the sample
# baseline reaches every top-level branch of a `case config["x"]` dispatch,
# which is the shape essentially all of these generators use, and is what
# catches the `currency_convert` class of bug.
#
# `visibleWhen` anchors are satisfied through
# `GeneratorConformance.visible_baseline`, so a conditional field is varied
# under the configuration that actually exposes it in the property editor
# (rather than under a config where the editor hides it).
module GeneratorBranchVariants
  # Hard cap on configurations emitted per generator. Sized to comfortably
  # exceed the largest real generator (the widest today needs ~40) while
  # bounding worst-case cost if someone adds a very large enum. When the cap
  # bites, `truncated?` reports it so the sweep can never silently shrink.
  MAX_VARIANTS_PER_GENERATOR = 96

  Variant = Struct.new(:label, :config, keyword_init: true)

  module_function

  # Select fields for an action, in a stable order so the sweep is
  # deterministic run to run.
  def enum_fields(action_key)
    GeneratorConformance.ui_fields(action_key)
                        .select { |f| f[:type].to_s == "select" }
                        .sort_by { |f| f[:key].to_s }
  end

  def option_values(field)
    Array(field[:options])
      .map { |o| (o["value"] || o[:value]).to_s }
      .reject(&:empty?)
      .uniq
  end

  # Every configuration worth emitting for this generator: the declared sample
  # input, plus one config per (select field, option) pair layered onto the
  # baseline that makes that field visible. Configs that are byte-identical to
  # one already collected are dropped, so the sweep does not re-emit the same
  # source repeatedly.
  def variants(generator_class, action_key)
    baseline = GeneratorConformance.baseline_config(generator_class) || {}
    seen = {}
    collected = []

    add = lambda do |label, config|
      return false if collected.size >= MAX_VARIANTS_PER_GENERATOR

      fingerprint = config.sort_by { |k, _| k.to_s }.inspect
      return true if seen.key?(fingerprint)

      seen[fingerprint] = true
      collected << Variant.new(label: label, config: config)
      true
    end

    add.call("sample_input", baseline)

    enum_fields(action_key).each do |field|
      key = field[:key].to_s
      visible = GeneratorConformance.visible_baseline(generator_class, field)
      option_values(field).each do |option|
        add.call("#{key}=#{option}", visible.merge(key => option))
      end
    end

    collected
  end

  # True when MAX_VARIANTS_PER_GENERATOR clipped the enumeration.
  def truncated?(generator_class, action_key)
    potential = 1 + enum_fields(action_key).sum { |f| option_values(f).size }
    potential > MAX_VARIANTS_PER_GENERATOR
  end
end
