# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mailers::ShellComponent, type: :component do
  def render_shell(**overrides)
    attrs = {
      preheader: "Preview this in your inbox.",
      brand: "Anysys",
      heading: "Sign in",
      title: "Sign in to your account",
      greeting: "Hi reader@example.com,",
      body: "Use the button below to continue.",
      action: "Continue",
      action_url: "https://anysys.test/go?token=abc",
      fallback: "If the button does not work, copy this link:",
      ignore: "If you did not request this, ignore this email.",
      footer: "Sent by Anysys."
    }.merge(overrides)

    render_inline(described_class.new(**attrs))
  end

  it "renders the hidden preheader for inbox previews" do
    render_shell

    expect(page).to have_css("div[style*='mso-hide:all']",
                             text: "Preview this in your inbox.",
                             visible: :all)
  end

  it "links the action URL on the button and the printed fallback" do
    render_shell

    expect(page).to have_css('a[href="https://anysys.test/go?token=abc"]', count: 2)
    expect(page).to have_link("Continue")
    expect(page.native.to_html).to include("#92400e")
    expect(page.native.to_html).to include("#f7f2ea")
  end

  it "keeps the headline separate from the greeting" do
    render_shell

    expect(page).to have_css("h1", text: "Sign in to your account")
    expect(page).to have_text("Hi reader@example.com,")
  end

  it "derives a letterhead monogram from the brand" do
    render_shell(brand: "Anysys")

    expect(page).to have_text("A")
    expect(described_class.new(**{
      preheader: "p", brand: " anysys", heading: "h", title: "t",
      body: "b", footer: "f"
    }).monogram).to eq("A")
  end

  it "omits the button and fallback when there is no action URL" do
    render_shell(action: nil, action_url: nil, fallback: nil)

    expect(page).not_to have_link("Continue")
    expect(page).not_to have_text("If the button does not work")
  end

  it "renders a highlight amount and labeled fact rows" do
    render_shell(
      action: nil,
      action_url: nil,
      fallback: nil,
      highlight: "CNY 99.00",
      highlight_caption: "Amount due",
      facts: [
        { label: "Invoice number", value: "INV-1" },
        { label: "Plan", value: "Pro Plan", emphasize: true },
        { label: "Due date", value: nil }
      ]
    )

    expect(page).to have_text("Amount due")
    expect(page).to have_text("CNY 99.00")
    expect(page).to have_text("Invoice number")
    expect(page).to have_text("INV-1")
    expect(page).to have_text("Pro Plan")
    expect(page).to have_text(I18n.t("mailers.shell.blank_value"))
    expect(page.native.to_html).to include("'Segoe UI'")
    expect(page.native.to_html).to include("Georgia")
    expect(page.native.to_html).not_to include("&#39;Segoe UI&#39;")
  end

  it "does not render a fact table when facts are empty" do
    render_shell(facts: [])

    expect(page).not_to have_text("Invoice number")
  end
end
