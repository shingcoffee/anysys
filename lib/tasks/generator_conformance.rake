# frozen_string_literal: true

namespace :conformance do
  desc "Write the per-category generator conformance defect inventory"
  task inventory: :environment do
    require Rails.root.join("spec/support/generator_conformance").to_s
    require "yaml"

    output = Hash.new { |h, k| h[k] = {} }

    CodeGenerators::GeneratorRegistry.step_action_generators.each do |action_key, klass|
      category = klass.name.split("::")[-2].underscore
      fields = GeneratorConformance.ui_fields(action_key)

      inert = fields.select do |f|
        GeneratorConformance.field_delta(klass, action_key, f) == :inert &&
          !GeneratorConformance.allow_listed?(action_key, f[:key])
      end.map { |f| f[:key].to_s }

      identical_enums = fields.select { |f| f[:type]&.to_sym == :select }.select do |f|
        digests = GeneratorConformance.enum_coverage(klass, action_key, f)
        digests.size > 1 && digests.values.uniq.size == 1
      rescue StandardError
        true
      end.map { |f| f[:key].to_s }

      leaks = fields.select { |f| f[:visibleWhen] }.select do |f|
        GeneratorConformance.visibility_leak?(klass, action_key, f)
      end.map { |f| f[:key].to_s }

      next if inert.empty? && identical_enums.empty? && leaks.empty?

      output[category][action_key] = {
        "inert_fields" => inert,
        "identical_enum_options" => identical_enums,
        "visibility_leaks" => leaks
      }
    end

    path = Rails.root.join(".superpowers/sdd/conformance-inventory.yml")
    File.write(path, output.to_h.deep_stringify_keys.to_yaml)
    total = output.values.sum(&:size)
    puts "Wrote inventory for #{total} actions with defects to #{path}"
  end
end
