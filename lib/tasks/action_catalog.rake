# frozen_string_literal: true

namespace :action_catalog do
  desc "Regenerate spec/javascript/fixtures/action_catalog.sample.json from the English catalog subset"
  task fixture: :environment do
    require Rails.root.join("spec/support/phase3_fixture_generator")

    path = Rails.root.join("spec/javascript/fixtures/action_catalog.sample.json")
    payload = CodeGenerators::ActionCatalog.sample_export(locale: "en")
    FileUtils.mkdir_p(path.dirname)
    File.write(path, "#{JSON.pretty_generate(payload)}\n")
    puts "Wrote #{path} (#{File.size(path)} bytes, #{payload.fetch("actions").size} actions)"
  end
end
