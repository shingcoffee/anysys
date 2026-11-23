# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Admin::TestConnectionResultComponent, type: :component do
  describe "#initialize" do
    it "defaults to :idle state" do
      component = described_class.new
      expect(component.state).to eq(:idle)
    end

    it "accepts :loading state" do
      component = described_class.new(state: :loading)
      expect(component.state).to eq(:loading)
    end

    it "accepts :success state with message" do
      component = described_class.new(state: :success, message: "Connection verified")
      expect(component.state).to eq(:success)
      expect(component.message).to eq("Connection verified")
    end

    it "accepts :error state with message" do
      component = described_class.new(state: :error, message: "Invalid API key")
      expect(component.state).to eq(:error)
      expect(component.message).to eq("Invalid API key")
    end

    it "accepts verified_at timestamp" do
      ts = Time.current
      component = described_class.new(state: :success, message: "OK", verified_at: ts)
      expect(component.verified_at).to eq(ts)
    end
  end

  describe "rendering" do
    context "idle state" do
      it "renders a container with hidden class" do
        render_inline(described_class.new(state: :idle))
        expect(page).to have_css("[data-payments--gateway-config-target='result'].hidden")
      end
    end

    context "loading state" do
      it "renders loading spinner" do
        render_inline(described_class.new(state: :loading))
        expect(page).to have_text("Testing connection")
      end

      it "renders animated spinner SVG" do
        render_inline(described_class.new(state: :loading))
        expect(page).to have_css("svg")
      end
    end

    context "success state" do
      let(:verified_at) { Time.zone.parse("2026-06-21 14:32:00 UTC") }

      it "renders success message" do
        render_inline(described_class.new(state: :success, message: "Connection verified", verified_at: verified_at))
        expect(page).to have_text("Connection verified")
      end

      it "renders success styling" do
        render_inline(described_class.new(state: :success, message: "Connection verified"))
        expect(page).to have_css("[class*='success']")
      end

      it "renders verified_at timestamp when present" do
        render_inline(described_class.new(state: :success, message: "OK", verified_at: verified_at))
        expect(page).to have_text("Last verified")
        expect(page).to have_text(I18n.l(verified_at, format: :long))
        expect(page).not_to have_text(verified_at.strftime("%Y-%m-%d %H:%M UTC"))
      end

      it "localizes verified_at in zh-CN" do
        I18n.with_locale(:"zh-CN") do
          render_inline(described_class.new(state: :success, message: "OK", verified_at: verified_at))
          expect(page).to have_text(I18n.l(verified_at, format: :long))
        end
      end
    end

    context "error state" do
      it "renders error message" do
        render_inline(described_class.new(state: :error, message: "Invalid API key (401)"))
        expect(page).to have_text("Invalid API key (401)")
      end

      it "renders error styling" do
        render_inline(described_class.new(state: :error, message: "Connection failed"))
        expect(page).to have_css("[class*='danger']")
      end

      it "renders 'Connection failed' heading" do
        render_inline(described_class.new(state: :error, message: "Timeout"))
        expect(page).to have_text("Connection failed")
      end
    end

    it "renders the target attribute for Stimulus" do
      render_inline(described_class.new(state: :idle))
      expect(page).to have_css("[data-payments--gateway-config-target='result']")
      expect(page).to have_css("[role='status'][aria-live='polite']")
      expect(page).not_to have_css("h1")
      expect(page).not_to have_link("Settings")
    end
  end
end
