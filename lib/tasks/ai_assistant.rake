# frozen_string_literal: true

namespace :ai_assistant do
  desc "Regenerate the flowchart assistant palette snapshot from ActionCatalog"
  task flowchart_schema: :environment do
    FlowchartDefinitions::Palette.reset!
    path = FlowchartDefinitions::Assistant::SchemaGenerator.write!
    document = FlowchartDefinitions::Assistant::SchemaGenerator.palette_document
    puts "Wrote #{path} (#{File.size(path)} bytes, #{document.fetch("step_actions").size} actions)"
  end
end
