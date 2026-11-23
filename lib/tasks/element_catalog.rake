# frozen_string_literal: true

namespace :element_catalog do
  desc "Regenerate spec/javascript/fixtures/element_catalog.sample.json from the English element catalog"
  task fixture: :environment do
    path = Rails.root.join("spec/javascript/fixtures/element_catalog.sample.json")
    payload = CodeGenerators::ElementCatalog.export(locale: "en")
    FileUtils.mkdir_p(path.dirname)
    File.write(path, "#{JSON.pretty_generate(payload)}\n")
    puts "Wrote #{path} (#{File.size(path)} bytes, #{payload.fetch("types").size} element types)"
  end
end
