# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::AuthShellComponent, type: :component do
  let(:customer) { create(:customer, name: "Acme") }

  it "renders the brand pane with the customer name on the neutral card" do
    render_inline(described_class.new(
      customer: customer, title: "Welcome back", subtitle: "Sign in to your account"
    )) { "<form>x</form>".html_safe }

    expect(page).to have_css("[data-shell='member-auth'].bg-canvas")
    expect(page).to have_css("aside[data-pane='brand'].bg-canvas-elevated")
    expect(page).to have_text("Acme")
    expect(page).to have_css("h1", text: "Welcome back")
    expect(page).to have_text("Sign in to your account")
  end

  it "falls back to the generic product name when no customer is present" do
    render_inline(described_class.new(
      customer: nil, title: "Welcome back", subtitle: "Sign in to continue."
    )) { "<form>x</form>".html_safe }

    expect(page).to have_text(I18n.t("member.auth_shell.portal_name"))
  end

  it "does not render member-oriented highlight pills" do
    render_inline(described_class.new(
      customer: customer, title: "Welcome back", subtitle: "Sign in to continue."
    )) { "<form>x</form>".html_safe }

    expect(page).not_to have_text("Manage your profile")
    expect(page).not_to have_text("Track payments")
    expect(page).not_to have_text("Stay secure")
  end

  it "uses neither the saturated gradient hero nor a tinted paper background" do
    render_inline(described_class.new(
      customer: customer, title: "x", subtitle: "y"
    )) { "<form>x</form>".html_safe }

    expect(page).not_to have_css(".hero-member")
    expect(page).not_to have_css(".auth-brand-pane, .bg-member-paper, .bg-warm-sand")
  end

  it "renders the form content slot on the right pane" do
    render_inline(described_class.new(
      customer: customer, title: "x", subtitle: "y"
    )) { "<form data-slot='form'></form>".html_safe }

    expect(page).to have_css("[data-pane='form'] form[data-slot='form']")
  end
end
