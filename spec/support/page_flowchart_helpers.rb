# frozen_string_literal: true

# Flowcharts that process page submissions. A new page binds the shared
# "Save page record" default, so most specs need nothing here; these build a
# page's own flowchart when a spec needs extra steps or hand-written code.
module PageFlowchartHelpers
  SAVE_STEPS = [{ "action" => "build_contract" }, { "action" => "validate_contract" }, { "action" => "save_model" }].freeze

  # A launched flowchart owned by +customer+ (nil: shared) that validates and
  # saves the page record, running +steps+ (generator steps, e.g.
  # { "action" => "register_member", "config" => {...} }) before the save.
  # +code+ (a full Trailblazer activity) or +body+ (one step's body) replaces
  # the compiled activity.
  def create_page_flowchart(customer:, steps: [], code: nil, body: nil)
    traits = customer ? [] : [:shared_type]
    flowchart = create(:flowchart, *traits, :launched_status, customer: customer,
                                                              configuration: page_flowchart_configuration(steps).to_json)
    code ||= body && <<~RUBY
      class SpecPageFlowchart#{SecureRandom.hex(4)} < Trailblazer::Activity::Railway
        CANVAS = { steps: {} }.freeze
        step :run
        def run(ctx, **)
          #{body}
        end
      end
    RUBY
    flowchart.update_column(:activity, code || ActivityGenerator.new(flowchart).generate)
    flowchart
  end

  # Binds +page+ to a new flowchart built by #create_page_flowchart.
  def bind_page_flowchart(page, **options)
    create_page_flowchart(customer: page.customer, **options).tap do |flowchart|
      page.update_column(:flowchart_id, flowchart.id)
    end
  end

  private

  def page_flowchart_configuration(steps)
    processes = (SAVE_STEPS.first(2) + steps + SAVE_STEPS.last(1)).each_with_index.map do |step, index|
      { "id" => "process_#{index + 1}", "type" => "process", "label" => step["action"].humanize, "properties" => { "steps" => [step] } }
    end
    elements = [{ "id" => "start_1", "type" => "start", "label" => "Start", "properties" => {} }, *processes,
                { "id" => "end_1", "type" => "end", "label" => "End", "properties" => {} }]
    {
      "elements" => elements.each_with_index.map { |element, index| element.merge("x" => 100, "y" => 100 * (index + 1), "width" => 100, "height" => 45) },
      "connections" => elements.each_cons(2).each_with_index.map { |(from, to), index| { "id" => "conn_#{index + 1}", "from" => from["id"], "to" => to["id"] } },
      "metadata" => {}
    }
  end
end

RSpec.configure do |config|
  config.include PageFlowchartHelpers

  # An example without a wrapping transaction commits the shared flowcharts
  # its pages bind; drop them again so later examples on the worker create their own.
  config.around do |example|
    next example.run if example.example_group.use_transactional_tests

    singletons = [Flowcharts::DefaultPageFlowchart::UUID, Flowcharts::SignUpPageFlowchart::UUID]
    existed = Flowchart.unscoped.where(uuid: singletons).pluck(:uuid)
    begin
      example.run
    ensure
      Flowchart.unscoped.where(uuid: singletons - existed).destroy_all
    end
  end
end
