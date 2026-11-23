# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Assistant::Uploads do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer) }

  def user_message(conversation, customer: conversation.customer)
    create(:ai_assistant_message, conversation: conversation, customer: customer)
  end

  def attach(message, filename, width: nil, height: nil)
    Current.set(customer: message.customer) do
      message.images.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/test.png")),
        filename: filename,
        content_type: "image/png"
      )
    end
    attachment = message.images.attachments.max_by(&:id)
    if width
      blob = attachment.blob
      blob.update!(metadata: blob.metadata.merge("width" => width, "height" => height))
    end
    attachment
  end

  describe "#all" do
    it "lists user-message images by message id, then attachment id" do
      first = user_message(conversation)
      second = user_message(conversation)
      b = attach(second, "b.png")
      a1 = attach(first, "a1.png", width: 1600, height: 1067)
      a2 = attach(first, "a2.png")

      uploads = described_class.new(conversation: conversation).all

      expect(uploads.map(&:token)).to eq([ a1, a2, b ].map { |row| "upload:#{row.id}" })
      expect(uploads.first).to have_attributes(
        filename: "a1.png",
        width: 1600,
        height: 1067,
        orientation: "landscape",
        message_id: first.id,
        pending: true
      )
      expect(uploads.second).to have_attributes(width: nil, height: nil, orientation: nil)
    end

    it "ignores assistant messages, other conversations and other tenants" do
      own = attach(user_message(conversation), "own.png")
      assistant = create(:ai_assistant_message, :assistant, conversation: conversation, customer: customer)
      attach(assistant, "assistant.png")
      attach(user_message(create(:ai_assistant_conversation, customer: customer)), "other_chat.png")
      attach(user_message(create(:ai_assistant_conversation, customer: other_customer)), "other_tenant.png")

      expect(described_class.new(conversation: conversation).all.map(&:token)).to eq([ "upload:#{own.id}" ])
    end

    it "skips a message stamped with another customer even inside the conversation" do
      stray = create(:ai_assistant_message, conversation: conversation, customer: other_customer)
      attach(stray, "stray.png")

      expect(described_class.new(conversation: conversation).all).to be_empty
    end

    it "skips a blob stamped for another tenant" do
      attachment = attach(user_message(conversation), "foreign.png")
      attachment.blob.update!(customer_id: other_customer.id)

      expect(described_class.new(conversation: conversation).all).to be_empty
    end

    it "is empty without a conversation" do
      expect(described_class.new(conversation: nil).all).to eq([])
    end
  end

  describe "#find and #pending" do
    it "resolves only tokens of this conversation" do
      attachment = attach(user_message(conversation), "shop.png")
      foreign = attach(user_message(create(:ai_assistant_conversation, customer: other_customer)), "x.png")
      uploads = described_class.new(conversation: conversation)

      expect(uploads.find("upload:#{attachment.id}").attachment).to eq(attachment)
      expect(uploads.find("upload:#{foreign.id}")).to be_nil
      expect(uploads.find("upload:abc")).to be_nil
      expect(uploads.find(nil)).to be_nil
    end

    def place_on_site(attachment)
      website = Website.find_by(customer_id: customer.id) || create(:website, customer: customer)
      url = Websites::Activities::ImportMedia.call(customer: customer, blob: attachment.blob).url
      create(:website_page, website: website, customer: customer, slug: "p#{attachment.id}", position: attachment.id,
        sections: [ { "id" => "sec_1", "type" => "hero_split", "props" => { "headline" => "Hi", "visual_url" => url } } ])
    end

    it "drops an upload from #pending while its imported copy is on a page" do
      placed = attach(user_message(conversation), "placed.png")
      fresh = attach(user_message(conversation), "fresh.png")
      place_on_site(placed)

      pending = described_class.new(conversation: conversation).pending

      expect(pending.map(&:token)).to eq([ "upload:#{fresh.id}" ])
    end

    it "offers an upload again once its photo has been removed from every page" do
      removed = attach(user_message(conversation), "removed.png")
      place_on_site(removed).update!(sections: [ { "id" => "sec_1", "type" => "statement", "props" => { "headline" => "Hi" } } ])

      pending = described_class.new(conversation: conversation).pending

      expect(pending.map(&:token)).to eq([ "upload:#{removed.id}" ])
    end
  end

  describe ".token? and .token_for" do
    it "recognizes only exact upload tokens" do
      expect(described_class.token?("upload:45")).to be(true)
      expect(described_class.token?("upload:")).to be(false)
      expect(described_class.token?(" upload:45")).to be(false)
      expect(described_class.token?("https://example.com/upload:45")).to be(false)
      expect(described_class.token?(45)).to be(false)
    end

    it "builds the token from the attachment id" do
      attachment = attach(user_message(conversation), "shop.png")

      expect(described_class.token_for(attachment)).to eq("upload:#{attachment.id}")
    end
  end

  describe ".orientation" do
    it "classifies by aspect ratio with a square tolerance" do
      expect(described_class.orientation(1600, 1067)).to eq("landscape")
      expect(described_class.orientation(800, 1200)).to eq("portrait")
      expect(described_class.orientation(1000, 1050)).to eq("square")
      expect(described_class.orientation(nil, nil)).to be_nil
    end
  end

  describe ".manifest_line" do
    it "lists tokens, filenames and known dimensions in attachment order" do
      message = user_message(conversation)
      storefront = attach(message, "storefront.jpg", width: 1600, height: 1067)
      chef = attach(message, "chef.png")

      line = described_class.manifest_line(described_class.ordered(message.reload))

      expect(line).to eq(
        %(Attached images, in order: upload:#{storefront.id} "storefront.jpg" (landscape 1600x1067); ) +
        %(upload:#{chef.id} "chef.png")
      )
    end

    it "is nil without attachments" do
      expect(described_class.manifest_line([])).to be_nil
      expect(described_class.manifest_line(nil)).to be_nil
    end
  end
end
