# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::AgendaComponent, type: :component do
  let(:props) do
    {
      "kicker" => "Day one",
      "heading" => "Beginnings",
      "sessions" => [
        { "time" => "09:00", "title" => "Opening session", "speaker" => "Ayo Adeyemi", "body" => "Six speakers revisit an idea.", "track" => "Main stage" },
        { "time" => "13:00", "title" => "Long lunch" },
        { "time" => "15:00", "title" => "" }
      ]
    }
  end

  it "renders one row per titled session with time, speaker and track" do
    render_inline(described_class.new(props: props, theme: website_theme, customer_id: 42))

    expect(page).to have_css("h2", text: "Beginnings")
    expect(page).to have_css("ol > li", count: 2)
    row = page.find("li", text: "Opening session")
    expect(row).to have_text("09:00")
    expect(row).to have_text("Ayo Adeyemi")
    expect(row).to have_text("Six speakers revisit an idea.")
    expect(row).to have_css("span.rounded-full", text: "Main stage")
  end

  it "omits the speaker and track when absent" do
    render_inline(described_class.new(props: props, theme: website_theme("appearance" => "dark"), customer_id: 42))

    row = page.find("li", text: "Long lunch")
    expect(row).not_to have_css("span.rounded-full")
  end

  it "renders a style override on the session title" do
    render_inline(described_class.new(
      props: props.merge("styles" => { "sessions.title" => { "color" => "#be123c" } }),
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_css("[data-site-el='sessions.title'][style*='#be123c']")
  end
end
