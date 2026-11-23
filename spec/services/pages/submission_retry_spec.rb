# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::SubmissionRetry do
  let(:customer) { create(:customer) }
  let(:page) { create(:page, customer: customer) }
  let(:other_page) { create(:page, customer: customer) }
  let(:session) { {} }

  def store(run: nil, values: { "name" => "Ada" }, field_errors: { "name" => ["taken"] })
    described_class.store(run: run, page: page, values: values, field_errors: field_errors,
                          customer_id: customer.id, user: nil, session: session)
  end

  it "issues a run pinned to the browser when the visitor has none, and shows it once" do
    token = store
    run = JourneyRun.find_usable(token: token, customer_id: customer.id, user: nil, session: session)

    expect(described_class.take(run, other_page)).to be_nil
    expect(described_class.take(run, page)).to eq("values" => { "name" => "Ada" }, "field_errors" => { "name" => ["taken"] })
    expect(described_class.take(run.reload, page)).to be_nil
  end

  it "keeps it on the visitor's own run, leaving the rest of the run alone" do
    journey = create(:journey, customer: customer)
    run, _token = JourneyRun.issue!(customer_id: customer.id, user: nil, session: session,
                                    journey: journey, current_step: "start",
                                    state: { "records" => { "start" => ["7"] } })

    expect(store(run: run)).to be_nil
    expect(described_class.take(run.reload, page)["values"]).to eq("name" => "Ada")
    expect(run.reload.records).to eq("start" => ["7"])
  end

  it "keeps nothing when there is nothing to show" do
    expect { expect(store(values: {}, field_errors: {})).to be_nil }.not_to change(JourneyRun, :count)
  end

  it "drops values that aren't short strings" do
    store(values: { "long" => "x" * (Pages::ActionLink::MAX_PREFILL_VALUE + 1), "list" => %w[a b], "ok" => "fine" })

    expect(JourneyRun.last.state_json.dig("retry", "values")).to eq("ok" => "fine")
  end
end
