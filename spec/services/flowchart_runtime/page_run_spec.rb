# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::PageRun do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Title", "name_slug" => "title", "type" => "String", "html_type" => "text" }
    ].to_json)
  end
  let(:page) do
    Current.set(customer: customer) do
      create(:page, :for_public, customer: customer, entity: entity, launched: true,
                    configuration: {
                      form_settings: { modes: ["create"] },
                      metadata: { entity_id: entity.id, entity_name: entity.name },
                      pages: [{ "id" => "p1", "fields" => [
                        { "id" => "f_title", "property_slug" => "title", "source" => "entity", "html_type" => "text" }
                      ] }]
                    }.to_json)
    end
  end

  def context_for(page, params: { "entity" => { "title" => "Hello" } }, viewer: nil, bindings: {})
    params = params.with_indifferent_access
    audience = EntityAttributeAudience.for_user(viewer, customer_id: customer.id)
    target = Pages::Submission::Target.resolve(
      page: page, entity: page.entity, entry_id: params[:entry_id],
      audience: audience, viewer: viewer, customer_id: customer.id
    )
    input = Pages::Submission::Input.permit(
      page: page, entity: page.entity, params: params, bindings: bindings,
      audience: audience, viewer: viewer, customer_id: customer.id
    )
    Pages::Submission::Context.new(
      page: page, target: target, input: input, audience: audience, viewer: viewer,
      authentication: nil, continuation: nil, journey: nil,
      request: { request_ip: "127.0.0.1", user_agent: "RSpec", locale: "en",
                 request_id: "spec", device_type: "desktop" }
    )
  end

  def run!(page, **options, &handoff)
    described_class.call(flowchart: page.flowchart, context: context_for(page, **options), &handoff)
  end

  it "runs the launched version while a saved draft version is pending" do
    flowchart = bind_page_flowchart(page)
    draft = JSON.parse(flowchart.configuration)
    draft["elements"].reject! { |el| el.dig("properties", "steps", 0, "action") == "save_model" }
    draft["connections"] = draft["elements"].each_cons(2).each_with_index.map do |(from, to), index|
      { "id" => "conn_#{index + 1}", "from" => from["id"], "to" => to["id"] }
    end
    flowchart.reload.update!(configuration: draft.to_json)
    expect(flowchart.reload).to be_pending_draft

    expect { expect(run!(page.reload)).to be_ok }.to change(EntityEntry, :count).by(1)

    flowchart.launch!
    expect { run!(page.reload) }.not_to change(EntityEntry, :count)
  end

  it "rolls back writes when the flowchart refuses" do
    bind_page_flowchart(page, body: <<~RUBY)
      ctx[:model].data_json = { "title" => "temp" }
      ctx[:model].save!
      ctx[:errors] = ["nope"]
      false
    RUBY

    expect { run!(page) }.not_to change(EntityEntry, :count)
    result = run!(page)
    expect(result).not_to be_ok
    expect(result.errors).to eq(["nope"])
    expect(result.entry).to be_nil
  end

  it "resolves page_record to a replacement the flowchart saved for the page's entity" do
    bind_page_flowchart(page, body: <<~RUBY)
      replacement = EntityEntry.build_for(ctx[:bound_entity]).new(
        entity: ctx[:bound_entity], customer_id: ctx[:customer_id], data: { "title" => "other" }.to_json
      )
      replacement.save!
      ctx[:model] = replacement
      true
    RUBY

    result = run!(page)

    expect(result).to be_ok
    expect(result.entry.data_json["title"]).to eq("other")
    expect(result.entry.entity_id).to eq(entity.id)
  end

  it "destroys a created page_record when the flowchart sets discard_record" do
    bind_page_flowchart(page, body: <<~RUBY)
      ctx[:model].data_json = { "title" => "gone" }
      ctx[:model].save!
      ctx[:discard_record] = true
      ctx[:submission_outcome] = { "preset" => "registration_pending" }
      true
    RUBY

    result = nil
    expect { result = run!(page) }.not_to change(EntityEntry, :count)
    expect(result).to be_ok
    expect(result.entry).to be_nil
    expect(result.outcome).to include("preset" => "registration_pending")
  end

  it "keeps an existing record the flowchart found when it sets discard_record" do
    existing = EntityEntry.build_for(entity).create!(entity: entity, customer_id: customer.id,
                                                     data: { "title" => "existing" }.to_json)
    bind_page_flowchart(page, body: <<~RUBY)
      ctx[:model] = EntityEntry.find(#{existing.id})
      ctx[:discard_record] = true
      true
    RUBY

    result = nil
    expect { result = run!(page) }.not_to change(EntityEntry, :count)
    expect(result).to be_ok
    expect(result.entry).to be_nil
    expect(EntityEntry.exists?(existing.id)).to be(true)
  end

  it "pads the registration timing even when the flowchart raises after starting the clock" do
    allow(Authentication::UniformTiming).to receive(:pad)
    bind_page_flowchart(page, body: <<~RUBY)
      ctx[:uniform_timing_started_at] = 42.0
      true
    RUBY
    result = run!(page) { raise ActiveRecord::StatementInvalid, "boom" }

    expect(result).not_to be_ok
    expect(Authentication::UniformTiming).to have_received(:pad).with(42.0)
  end

  it "calls the handoff block with the entry and outcome" do
    bind_page_flowchart(page, body: <<~RUBY)
      ctx[:model].data_json = { "title" => "Hello" }
      ctx[:model].save!
      ctx[:submission_outcome] = { "preset" => "saved", "handoff" => { "module_key" => "demo" } }
      true
    RUBY

    yielded = nil
    result = run!(page) do |entry, outcome|
      yielded = [entry, outcome]
      true
    end

    expect(result).to be_ok
    expect(result.handed_off).to be(true)
    expect(yielded[0].id).to eq(result.entry.id)
    expect(yielded[1]).to include("preset" => "saved", "handoff" => { "module_key" => "demo" })
  end

  it "turns a raised exception into activity_execution_failed" do
    bind_page_flowchart(page, body: "raise 'boom'")

    result = run!(page)

    expect(result).not_to be_ok
    expect(result.errors).to eq([I18n.t("common.errors.dynamic.activity_execution_failed")])
    expect(result.entry).to be_nil
  end

  it "refuses with the handoff error message when the block raises ModuleNotEnabled" do
    bind_page_flowchart(page, body: <<~RUBY)
      ctx[:model].data_json = { "title" => "Hello" }
      ctx[:model].save!
      true
    RUBY

    result = run!(page) { |_entry, _outcome| raise FeatureModules::ModuleNotEnabled, "module down" }

    expect(result).not_to be_ok
    expect(result.errors).to eq(["module down"])
    expect(EntityEntry.where(entity_id: entity.id)).to be_empty
  end
end
