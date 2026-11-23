# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Href do
  describe ".valid?" do
    it "accepts a kebab-case slug" do
      expect(described_class.valid?("about")).to be(true)
      expect(described_class.valid?("see-our-work")).to be(true)
    end

    it "accepts an https URL" do
      expect(described_class.valid?("https://example.com/work")).to be(true)
    end

    ["/auth/sign_up", "/81721200/admin", "/path?query#frag", "/", "/path//child", " /auth/sign_up "].each do |href|
      it "accepts and resolves the same-origin path #{href.inspect}" do
        expect(described_class.valid?(href)).to be(true)
        expect(described_class.resolve(href, customer_id: "12345678")).to eq(href.strip)
        expect(described_class.error_message(href)).to be_nil
      end
    end

    [
      "//evil.example/phish", "///evil.example", "/\\evil.example/phish", "\\\\evil.example",
      "/path\\child", "/path?query=\\host", "/path#\\host", "/path with spaces",
      "https://safe.example\\@evil.example", "/\t/evil.example", "/\n/evil.example", "/\r/evil.example"
    ].each do |href|
      it "rejects and does not resolve the unsafe href #{href.inspect}" do
        expect(described_class.valid?(href)).to be(false)
        expect(described_class.resolve(href, customer_id: "12345678")).to be_nil
        expect(described_class.error_message(href)).to eq(I18n.t("website.errors.invalid_href"))
      end
    end

    it "rejects raw controls before trimming or URL parsing can erase them" do
      ((0..31).to_a + (127..159).to_a).each do |code|
        control = code.chr(Encoding::UTF_8)
        [control, "#{control}/auth/sign_up", "/auth/sign_up#{control}", "/#{control}/evil.example", "https://safe.example/#{control}path"].each do |href|
          expect(described_class.valid?(href)).to be(false), href.inspect
          expect(described_class.resolve(href, customer_id: "12345678")).to be_nil, href.inspect
        end
      end
    end

    it "accepts a blank value" do
      expect(described_class.valid?("")).to be(true)
      expect(described_class.valid?(nil)).to be(true)
    end

    it "rejects javascript:, data:, and http://" do
      expect(described_class.valid?("javascript:alert(1)")).to be(false)
      expect(described_class.valid?("JavaScript:alert(1)")).to be(false)
      expect(described_class.valid?("data:text/html,hi")).to be(false)
      expect(described_class.valid?("http://example.com")).to be(false)
    end

    it "rejects https URLs without a host and unparsable URIs" do
      expect(described_class.valid?("https://")).to be(false)
      expect(described_class.valid?("https://[")).to be(false)
    end
  end

  describe ".error_message" do
    it "returns a javascript-specific message and a generic invalid href otherwise" do
      expect(described_class.error_message("javascript:alert(1)")).to eq(I18n.t("website.errors.javascript_href"))
      expect(described_class.error_message("http://example.com")).to eq(I18n.t("website.errors.invalid_href"))
      expect(described_class.error_message("about")).to be_nil
    end
  end

  describe ".resolve" do
    let(:cid) { "12345678" }

    it "maps a slug onto a clean tenant public path" do
      expect(described_class.resolve("about", customer_id: cid)).to eq("/#{cid}/about")
    end

    it "translates legacy website destinations and preserves repeated query pairs and fragments" do
      expect(described_class.resolve("/81721200/site", customer_id: cid)).to eq("/")
      expect(described_class.resolve("/81721200/site/pricing?tag=a&tag=b#plans", customer_id: cid))
        .to eq("/pricing?tag=a&tag=b#plans")
      expect(described_class.resolve("/12345678/site/media/token?download=1", customer_id: cid))
        .to eq("/12345678/site/media/token?download=1")
    end

    it "passes an explicit host to public path generation" do
      allow(PageShortcuts::PublicPath).to receive(:website_slug)
        .with(slug: "about", customer_id: cid, host: "tenant.example.com").and_return("/about")
      expect(described_class.resolve("about", customer_id: cid, host: "tenant.example.com")).to eq("/about")
    end

    it "translates only accessible public Page records through the public path service" do
      customer = create(:customer, id: cid)
      public_page = create(:page, :for_member, :for_public, customer: customer, launched: true)
      PageShortcut.create!(customer_id: customer.id, path: "/register", target: public_page)
      expect_any_instance_of(Page).not_to receive(:reload_definition_from_head!)
      expect(described_class.resolve("/#{cid}/page/#{public_page.public_uuid}?tag=a&tag=b#form", customer_id: cid))
        .to eq("/12345678/register?tag=a&tag=b#form")
    end

    it "keeps an https URL unchanged" do
      expect(described_class.resolve("https://example.com/work", customer_id: cid))
        .to eq("https://example.com/work")
    end

    it "keeps a root-relative path unchanged" do
      expect(described_class.resolve("/auth/sign_up", customer_id: cid)).to eq("/auth/sign_up")
    end

    it "returns nil for javascript:, data:, and http://" do
      expect(described_class.resolve("javascript:alert(1)", customer_id: cid)).to be_nil
      expect(described_class.resolve("data:text/html,hi", customer_id: cid)).to be_nil
      expect(described_class.resolve("http://example.com", customer_id: cid)).to be_nil
    end
  end

  describe ".media?" do
    let(:bundled_image) { "/site-images/anysys/anysys-home-workspace-hero.svg" }

    it "accepts https image URLs and tenant media paths" do
      expect(described_class.media?("https://cdn.example.com/hero.jpg")).to be(true)
      expect(described_class.media?("about")).to be(false)
      expect(described_class.media?("")).to be(false)
      expect(described_class.media?("javascript:alert(1)")).to be(false)
      expect(described_class.media?("http://cdn.example.com/hero.jpg")).to be(false)
      expect(described_class.media?("https://[")).to be(false)
      expect(described_class.media?("/12345678/site/media/abc--signed")).to be(true)
      expect(described_class.media?("/12345678/site/about")).to be(false)
      expect(described_class.media?("/12345678/site/media/abc/extra")).to be(false)
    end

    it "preserves signed https URLs and surrounding-space handling for existing media" do
      expect(described_class.media?(" https://cdn.example.com/hero.jpg?signature=abc&expires=123 ")).to be(true)
      expect(described_class.media?(" /12345678/site/media/abc--signed ")).to be(true)
      expect(described_class.media?(nil)).to be(false)
    end

    %w[
      anysys-home-workspace-hero.svg
      anysys-ai-draft.svg
      anysys-website-draft.svg
      anysys-brand-studio.svg
      anysys-review-publish.svg
      anysys-records-forms.svg
      anysys-members-payments.svg
      anysys-email-sms.svg
      anysys-local-desktop.svg
      anysys-record-control.svg
      anysys-local-privacy.svg
      anysys-pricing-growth-hero.svg
      anysys-platform-workspace-hero.svg
      anysys-about-idea-hero.svg
      anysys-contact-conversation-hero.svg
    ].each do |filename|
      it "accepts the documented bundled illustration #{filename}" do
        expect(described_class.media?("/site-images/anysys/#{filename}")).to be(true)
      end
    end

    it "accepts lowercase alphanumeric and hyphen illustration names" do
      expect(described_class.media?("/site-images/anysys/anysys-scene-2.svg")).to be(true)
    end

    it "accepts bundled marketing photos only under the exact anysys-photo WebP pattern" do
      expect(described_class.media?("/site-images/anysys/anysys-photo-studio-owner.webp")).to be(true)
      expect(described_class.media?("/site-images/anysys/anysys-photo-2.webp")).to be(true)
      [
        "/site-images/anysys/anysys-photo-.webp", "/site-images/anysys/anysys-photo-Team.webp",
        "/site-images/anysys/anysys-photo-team.jpg", "/site-images/anysys/anysys-photo-team.webp?x=1",
        "/site-images/anysys/anysys-photo-../secret.webp", "/site-images/anysys/anysys-photo-team.webp/extra",
        "/site-images/other/anysys-photo-team.webp", "//site-images/anysys/anysys-photo-team.webp"
      ].each { |path| expect(described_class.media?(path)).to be(false), path }
    end

    [
      "/assets/anysys-home-workspace-hero.svg",
      "/auth/sign_up",
      "/site-images/other/anysys-home-workspace-hero.svg",
      "/site-images/anysys/home-workspace-hero.svg",
      "/site-images/anysys/anysys-.svg",
      "/site-images/anysys/anysys-Home.svg",
      "/site-images/anysys/anysys-home_workspace.svg",
      "/site-images/anysys/anysys-插图.svg",
      "/site-images/anysys/anysys-home.svgz",
      "/site-images/anysys/anysys-home.SVG",
      "/site-images/anysys/anysys-home.webp",
      "/site-images/anysys/anysys-home.svg.html",
      "/site-images/anysys/anysys-home.svg/extra",
      "/site-images/anysys/anysys-home/child.svg",
      "/site-images/anysys/anysys-../secret.svg",
      "/site-images/anysys/../anysys-home.svg",
      "/site-images/anysys/./anysys-home.svg",
      "/site-images/anysys//anysys-home.svg",
      "/site-images/anysys/anysys-%2e%2e%2fsecret.svg",
      "/site-images/anysys/anysys-home%2fchild.svg",
      "/site-images/anysys/anysys-home%5cchild.svg",
      "/site-images/anysys/anysys-home%00.svg",
      "/site-images/anysys/anysys-home\\child.svg",
      "\\site-images\\anysys\\anysys-home.svg",
      "//site-images/anysys/anysys-home.svg",
      "///site-images/anysys/anysys-home.svg",
      "//evil.example/site-images/anysys/anysys-home.svg",
      "site-images/anysys/anysys-home.svg",
      "prefix/site-images/anysys/anysys-home.svg",
      "/site-images/anysys/anysys-home.svg?download=1",
      "/site-images/anysys/anysys-home.svg#fragment",
      " /site-images/anysys/anysys-home.svg",
      "/site-images/anysys/anysys-home.svg "
    ].each do |path|
      it "rejects media outside the exact bundled illustration pattern #{path.inspect}" do
        expect(described_class.media?(path)).to be(false)
      end
    end

    it "rejects raw controls anywhere in bundled illustration paths, including before trimming" do
      ((0..31).to_a + (127..159).to_a).each do |code|
        control = code.chr(Encoding::UTF_8)
        ["#{control}#{bundled_image}", "#{bundled_image}#{control}", "/site-images/anysys/anysys-home#{control}.svg"].each do |path|
          expect(described_class.media?(path)).to be(false), path.inspect
        end
      end
    end
  end
end
