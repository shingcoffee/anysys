# frozen_string_literal: true

require "rails_helper"
require "rubocop"

# Every generator's sample step must read like hand-written project Ruby: the
# project RuboCop config plus the cops below, which catch what string-built
# code tends to get wrong.
RSpec.describe "Generated step source style" do
  let(:style_config) do
    <<~YAML
      inherit_from: #{Rails.root.join('.rubocop.yml')}
      AllCops:
        NewCops: disable
        SuggestExtensions: false
      Layout/LineLength:
        Enabled: true
        Max: #{CodeGenerators::SourceFormatter::MAX_WIDTH}
      Layout/IndentationWidth:
        Enabled: true
      Layout/IndentationConsistency:
        Enabled: true
      Layout/BlockAlignment:
        Enabled: true
      Layout/EndAlignment:
        Enabled: true
      Layout/ClosingParenthesisIndentation:
        Enabled: true
      Layout/MultilineMethodCallBraceLayout:
        Enabled: true
      Layout/SpaceAroundOperators:
        Enabled: true
      Layout/SpaceInsideBlockBraces:
        Enabled: true
      Layout/TrailingWhitespace:
        Enabled: true
      Lint/UnderscorePrefixedVariableName:
        Enabled: true
      Lint/UselessAssignment:
        Enabled: true
      Style/RedundantParentheses:
        Enabled: true
      Style/RedundantReturn:
        Enabled: true
      Style/HashSyntax:
        Enabled: true
    YAML
  end

  def offenses_for(sources)
    Dir.mktmpdir do |dir|
      sources.each do |name, code|
        File.write(File.join(dir, "#{name}.rb"), "# frozen_string_literal: true\n\nclass GeneratedActivity\n#{code.indent(2)}\nend\n")
      end
      config = File.join(dir, "style.yml")
      report = File.join(dir, "report.json")
      File.write(config, style_config)

      run_quietly { RuboCop::CLI.new.run(["--config", config, "--format", "json", "--out", report, "--cache", "false", dir]) }

      JSON.parse(File.read(report)).fetch("files").flat_map do |file|
        file.fetch("offenses").map do |offense|
          "#{File.basename(file['path'])}:#{offense.dig('location', 'line')} #{offense['cop_name']}: #{offense['message']}"
        end
      end
    end
  end

  def run_quietly
    original = $stderr
    $stderr = StringIO.new
    yield
  ensure
    $stderr = original
  end

  it "emits RuboCop-clean steps for every generator's sample input" do
    sources = CodeGenerators::GeneratorRegistry.all.filter_map do |generator|
      code = generated_step(generator.sample_input, generator: generator)
      [generator.generator_name, code] if code
    end

    expect(sources.size).to be > 90
    offenses = offenses_for(sources)
    expect(offenses).to be_empty, offenses.join("\n")
  end
end
