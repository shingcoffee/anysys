# frozen_string_literal: true

# One command that runs EVERY generator/UI gate and fails if any of them
# reports a defect.
#
# Why this exists: the repository grew three independent audit scripts plus a
# conformance harness, each with its own entry point and its own exit
# convention. During a four-agent refactor every agent ran two of the three
# scripts and reported "clean" — while `scripts/audit_step_action_config.rb`,
# which nobody ran, was exiting 1 the whole time. A gate that must be assembled
# by hand from memory is not a gate.
#
# Adding a new check: append to CHECKS below. Anything not listed here is, by
# construction, a check people will forget to run.
namespace :audit do
  desc "Run every generator audit + conformance gate; exit non-zero if ANY sub-check reports a defect"
  task all: :environment do
    require "yaml"

    root = Rails.root.to_s
    results = []

    banner = lambda do |name, purpose, command|
      puts
      puts "=" * 78
      puts "▶ #{name}"
      puts "  detects: #{purpose}"
      puts "  $ #{command}"
      puts "=" * 78
    end

    record = lambda do |name, ok, detail|
      results << { name: name, ok: ok, detail: detail }
    end

    # --- 1. Railway checklist audit -----------------------------------------
    # The rake wrapper is used rather than the bare script because it prints the
    # offending generator and rule for each gap; the script prints only a count.
    name = "audit:generators"
    command = "bundle exec rake audit:generators"
    banner.call(name, "Railway-contract gaps: missing ctx guards, error handling, " \
                      "output declarations, sample_input", command)
    ok = system(command, chdir: root)
    record.call(name, ok, ok ? "no actionable gaps" : "actionable Railway gaps")

    # --- 2. Generator <-> UI schema audit -----------------------------------
    name = "scripts/audit_generator_ui.rb"
    command = "bundle exec ruby scripts/audit_generator_ui.rb"
    banner.call(name, "generator reads a key the editor never renders; missing " \
                      "registration/schema/builder action; visibility or default drift", command)
    ok = system(command, chdir: root)
    unless ok
      # The script reports only a count; surface the individual defects so the
      # gate is actionable without a second command.
      detail_script = %q(require "./scripts/audit_generator_ui"; ) +
                      %q(GeneratorUiAudit.run_report[:defects].each { |d| puts "  " + d.inspect })
      system("bundle", "exec", "ruby", "-e", detail_script, chdir: root)
    end
    record.call(name, ok, ok ? "no defects" : "generator/UI defects")

    # --- 3. Deep step-action config audit -----------------------------------
    name = "scripts/audit_step_action_config.rb"
    command = "bundle exec ruby scripts/audit_step_action_config.rb"
    banner.call(name, "editor renders a field the generator never reads (dead_ui_field); " \
                      "enum_drift / enum_gap; reserved key clash; required drift", command)
    ok = system(command, chdir: root)
    record.call(name, ok, ok ? "no defects" : "step action config defects")

    # --- 4. Semantic conformance inventory ----------------------------------
    # `conformance:inventory` writes its findings and always exits 0, so the
    # inventory file — not the exit status — is the authority here.
    name = "conformance:inventory"
    command = "bundle exec rake conformance:inventory"
    banner.call(name, "inert property-editor fields; all-identical enum options; " \
                      "visibleWhen visibility leaks", command)
    ran = system(command, chdir: root)
    inventory_path = Rails.root.join(".superpowers/sdd/conformance-inventory.yml")
    inventory = (YAML.load_file(inventory_path) if File.exist?(inventory_path)) || {}
    defect_actions = inventory.values.sum { |actions| actions.is_a?(Hash) ? actions.size : 0 }
    if !ran
      record.call(name, false, "inventory task failed to run")
    elsif defect_actions.positive?
      offenders = inventory.flat_map { |category, actions| actions.keys.map { |a| "#{category}/#{a}" } }
      puts "  #{defect_actions} action(s) with conformance defects: #{offenders.join(', ')}"
      record.call(name, false, "#{defect_actions} action(s) with conformance defects")
    else
      record.call(name, true, "0 actions with defects")
    end

    # --- 5. Conformance + tenant-scoping specs ------------------------------
    # The inventory above is deliberately coarser than the specs: it only flags
    # an enum whose options are ALL identical, and it checks neither tenant
    # scoping nor emission crashes. Without these specs the gate would pass a
    # partial duplicate-option collision, a cross-tenant key leak, or a
    # generator that raises on a valid non-sample branch.
    name = "conformance + branch sweep specs"
    spec_files = [
      "spec/services/code_generators/generator_conformance_spec.rb",
      "spec/services/code_generators/tenant_scoping_spec.rb",
      "spec/services/code_generators/branch_emission_spec.rb"
    ]
    command = "bundle exec rspec #{spec_files.join(' ')}"
    banner.call(name, "partial duplicate enum options; per-field inert/leak assertions; " \
                      "tenant scoping of every shared-namespace key on every branch; " \
                      "emission crashes and non-compiling source on any branch", command)
    ok = system(command, chdir: root)
    record.call(name, ok, ok ? "green" : "failing examples")

    # --- summary ------------------------------------------------------------
    puts
    puts "=" * 78
    puts "AUDIT SUMMARY"
    puts "=" * 78
    width = results.map { |r| r[:name].length }.max
    results.each do |result|
      puts format("  %-6s %-#{width}s  %s", result[:ok] ? "PASS" : "FAIL", result[:name], result[:detail])
    end

    failed = results.reject { |r| r[:ok] }
    if failed.any?
      puts
      $stdout.flush
      abort "audit:all FAILED — #{failed.size} of #{results.size} sub-checks reported defects: " \
            "#{failed.map { |r| r[:name] }.join(', ')}"
    end

    puts
    puts "audit:all PASSED — all #{results.size} sub-checks clean."
  end
end
