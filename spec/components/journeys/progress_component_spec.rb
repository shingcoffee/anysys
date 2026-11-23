# frozen_string_literal: true

require "rails_helper"

RSpec.describe Journeys::ProgressComponent, type: :component do
  let(:customer) { create(:customer) }
  let(:admin) { create(:user, :admin, customer: customer) }
  let(:steps) do
    [
      { "key" => "start", "kind" => "create", "action_key" => "student_new", "label" => "Student" },
      { "key" => "relate_1", "kind" => "relate", "action_key" => "student_add_course", "inputs" => { "student" => "start" } },
      { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "start" } }
    ]
  end
  let(:journey) { create(:journey, customer: customer, definition: { "steps" => steps }.to_json) }

  before do
    Current.customer = customer
    Current.user = admin
  end

  after { Current.reset }

  it "counts the working steps, checks off the done ones and marks the current one" do
    render_inline(described_class.new(journey: journey, current_key: "relate_1"))

    nav = page.find("[data-role='journey-progress']")
    expect(nav).to have_text(I18n.t("journeys.runtime.step_of", current: 2, total: 2))
    expect(nav["aria-label"]).to eq(I18n.t("journeys.runtime.step_of", current: 2, total: 2))
    expect(nav).to have_css("li", count: 2)
    done = nav.find("li[data-state='done']")
    expect(done).to have_css("span.bg-slate-900 svg")
    expect(done).to have_css(".sr-only", text: "1. Student")
    expect(done).to have_css("span.bg-slate-900[aria-hidden='true']")
    current = nav.find("li[aria-current='step']")
    expect(current["data-state"]).to eq("current")
    expect(current).to have_css("span.ring-slate-900", text: "2")
    expect(current).not_to have_css("span.h-0\\.5")
  end

  it "names the current step above the markers and marks upcoming steps" do
    render_inline(described_class.new(journey: journey, current_key: "start"))

    nav = page.find("[data-role='journey-progress']")
    expect(nav.find("p.font-semibold").text).to eq("Student")
    expect(nav.find("li[data-state='upcoming']")).to have_css("span.bg-slate-100", text: "2")
    expect(nav.find("li[data-state='current']")).to have_css("span.bg-slate-200[aria-hidden='true']")
  end

  it "shows only the count when the current step has no name" do
    render_inline(described_class.new(journey: journey, current_key: "relate_1"))

    nav = page.find("[data-role='journey-progress']")
    expect(nav.find("p.font-semibold").text).to eq(I18n.t("journeys.runtime.step_of", current: 2, total: 2))
    expect(nav).to have_css("p", count: 1)
  end

  it "labels an unlabelled step with the page the viewer's audience gets" do
    create(:page, customer: customer, launched: true, action_key: "student_add_course", name: "Add Course for Student")
    create(:page, customer: customer, launched: true, action_key: "student_add_course", name: "Public course page",
                  audience_admin: false, audience_public: true)

    render_inline(described_class.new(journey: journey, current_key: "relate_1"))

    expect(page).to have_css("li[aria-current='step']", text: "Add Course for Student")
    expect(page).not_to have_text("Public course page")
  end

  it "starts at the first step when the current key is unknown" do
    render_inline(described_class.new(journey: journey, current_key: nil))

    expect(page).to have_text(I18n.t("journeys.runtime.step_of", current: 1, total: 2))
    expect(page).to have_css("li[aria-current='step']", text: "Student")
  end

  it "counts a user step first, naming it the user account" do
    user_first = create(:journey, customer: customer, definition: { "steps" => [{ "key" => "user", "kind" => "user" }, *steps] }.to_json)
    allow(Pages::ActionResolver).to receive(:pages_for).and_call_original

    render_inline(described_class.new(journey: user_first, current_key: "user"))

    nav = page.find("[data-role='journey-progress']")
    expect(nav.find("p.font-semibold").text).to eq(I18n.t("journeys.runtime.user_step"))
    expect(nav).to have_text(I18n.t("journeys.runtime.step_of", current: 1, total: 3))
    expect(nav).to have_css("li", count: 3)
    expect(Pages::ActionResolver).to have_received(:pages_for).with(hash_including(action_keys: ["student_add_course"]))
  end

  it "shows an Optional badge beside an optional current step's label" do
    optional = steps.map(&:dup)
    optional[1] = optional[1].merge("optional" => true)
    record = create(:journey, customer: customer, definition: { "steps" => optional }.to_json)

    render_inline(described_class.new(journey: record, current_key: "relate_1"))

    nav = page.find("[data-role='journey-progress']")
    expect(nav.find("p.font-semibold").text).to eq(I18n.t("journeys.runtime.step_of", current: 2, total: 2))
    expect(nav).to have_css(".badge[aria-hidden='true']", text: I18n.t("journeys.optional"))
  end
end
