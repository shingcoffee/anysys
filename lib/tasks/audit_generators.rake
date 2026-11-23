# lib/tasks/audit_generators.rake
# Wraps scripts/audit_generators.rb so it can be invoked via `rake` in CI.

namespace :audit do
  desc "Audit every code generator against the canonical Railway checklist; exit non-zero on gaps (CI-ready)"
  task generators: :environment do
    load Rails.root.join("scripts/audit_generators.rb").to_s
    report = GeneratorAudit.run_audit
    GeneratorAudit.write_baseline(report)
    actionable = report.sum { |_, entry| entry[:gaps].reject { |g| g[:allowed] || g["allowed"] }.size }
    puts "Audit: #{report.size} generators, #{actionable} actionable gaps. Baseline: #{GeneratorAudit::BASELINE_PATH}"

    if actionable.positive?
      report.each do |name, entry|
        actionable_gaps = entry[:gaps].reject { |g| g[:allowed] || g["allowed"] }
        next if actionable_gaps.empty?
        puts "  #{name} (#{entry[:file]}):"
        actionable_gaps.each { |g| puts "    - [#{g[:rule]}] #{g[:message]}" }
      end
      exit 1
    end
  end

  namespace :generators do
    desc "Regenerate audit baseline YAML without failing on gaps (use when intentionally accepting the current state)"
    task baseline: :environment do
      load Rails.root.join("scripts/audit_generators.rb").to_s
      report = GeneratorAudit.run_audit
      GeneratorAudit.write_baseline(report)
      actionable = report.sum { |_, entry| entry[:gaps].reject { |g| g[:allowed] || g["allowed"] }.size }
      puts "Baseline regenerated: #{report.size} generators, #{actionable} actionable gaps captured in #{GeneratorAudit::BASELINE_PATH}"
    end
  end
end
