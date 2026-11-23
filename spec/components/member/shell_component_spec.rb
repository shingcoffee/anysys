# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::ShellComponent, type: :component do
  let_it_be(:customer) { create(:customer) }
  let(:user)     { create(:user, :member, customer: customer) }

  def render_shell(**opts, &block)
    block ||= proc { "page body" }
    render_inline(described_class.new(
      customer: customer, user: user, current_nav: :home, **opts
    ), &block)
  end

  it "renders the site-style top bar, the content column, and the wrapped content" do
    render_shell

    expect(page).to have_css("[data-shell='member']")
    expect(page).to have_css("header.sticky")
    expect(page).to have_text("page body")
  end

  it "wires the public site nav controller and closes it before Turbo caches the page" do
    render_shell

    root = page.find("[data-controller='website-nav']")
    expect(root["data-action"]).to include("turbo:before-cache@window->website-nav#close")
  end

  it "renders a mobile sheet backdrop that closes the menu on click" do
    render_shell

    scrim = page.find("[data-website-nav-target='backdrop']", visible: :all)
    expect(scrim["data-action"]).to eq("click->website-nav#close")
    expect(scrim["aria-hidden"]).to eq("true")
    expect(scrim[:class]).to include("hidden", "lg:hidden", "bg-black/40")
  end

  it "renders an accessible menu button for the mobile sheet" do
    render_shell

    button = page.find("button[data-website-nav-target='trigger']")
    expect(button["data-action"]).to eq("click->website-nav#toggle")
    expect(button["aria-expanded"]).to eq("false")
    expect(button["aria-controls"]).to eq("member-nav-panel")
    expect(button["aria-label"]).to eq("Open navigation")
    expect(button[:class]).to include("lg:hidden")
  end

  it "renders the customer name as the home link in the site nav" do
    render_shell

    expect(page).to have_link(customer.name, href: "/#{customer.id}/member")
  end

  it "uses the public site nav surface" do
    render_shell

    expect(page.find("header")[:class]).to include("bg-white/70", "backdrop-blur-xl")
  end

  it "applies the default site measure when none given" do
    render_shell

    expect(page).to have_css("main.max-w-7xl")
  end

  it "applies the narrow container width" do
    render_shell(container_width: :narrow)

    expect(page).to have_css("main.max-w-3xl")
  end

  it "renders content edge-to-edge when container_width is :edge" do
    render_shell(container_width: :edge)

    expect(page).not_to have_css("main.max-w-7xl")
    expect(page).to have_css("main.w-full")
  end

  it "raises on an unknown container width" do
    expect {
      described_class.new(customer: customer, user: user, current_nav: :home, container_width: :bogus)
    }.to raise_error(ArgumentError, /Unknown container_width/)
  end

  it "uses rounded-2xl on flash banners" do
    allow_any_instance_of(ActionDispatch::Flash::FlashHash).to receive(:any?).and_return(true)
    allow_any_instance_of(ActionDispatch::Flash::FlashHash).to receive(:each).and_yield("notice", "All good!")
    render_shell { "x" }

    expect(page).to have_css("div.rounded-2xl", text: "All good!")
  end
end
