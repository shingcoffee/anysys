# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::Prompt::Sections::WebsiteImages do
  let(:customer) { create(:customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer) }
  let(:context) { AiAssistant::Assistant::Prompt::Context.new(conversation: conversation.reload, mode: :entity) }

  def render = described_class.new(context).render

  def attach_image(filename, metadata = {})
    message = create(:ai_assistant_message, conversation: conversation, customer: customer)
    blob = Current.set(customer: customer) do
      ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("\x89PNG\r\n\x1A\n"), filename: filename, content_type: "image/png", metadata: metadata
      )
    end
    message.images.attach(blob)
    message.images.attachments.last
  end

  def upload(token:, pending: true, filename: "photo.jpg", byte_size: 1, **shape)
    blob = instance_double(ActiveStorage::Blob, byte_size: byte_size)
    Websites::Assistant::Uploads::Upload.new(token: token, filename: filename, pending: pending, blob: blob, **shape)
  end

  it "drops itself when the Website module is off" do
    attach_image("shop.png")

    expect(render).to be_nil
  end

  context "when the Website module is on" do
    before { enable_module!("website", customer) }

    it "drops itself when nothing was attached" do
      expect(render).to be_nil
    end

    it "lists each attached image by token with its filename, shape and placement" do
      attachment = attach_image("storefront.jpg", width: 1600, height: 1067)

      expect(render).to include(%(- `upload:#{attachment.id}` "storefront.jpg" · landscape 1600x1067 · not placed yet))
    end

    it "omits the shape when the image was never analyzed" do
      attachment = attach_image("chef.png")

      expect(render).to include(%(- `upload:#{attachment.id}` "chef.png" · not placed yet))
    end

    it "marks an image already imported into website media" do
      allow(context.uploads).to receive(:all).and_return(
        [upload(token: "upload:7", filename: "logo.png", pending: false, orientation: "square", width: 400, height: 400)]
      )

      expect(render).to include(%(- `upload:7` "logo.png" · square 400x400 · already on the website))
    end

    it "flattens a filename that would otherwise pose as prompt structure" do
      allow(context.uploads).to receive(:all).and_return([upload(token: "upload:8", filename: "a`\n## b.png")])

      expect(render).to include(%("a b.png"))
    end

    it "explains that only the newest images are shown as pictures once the replay cap is passed" do
      limit = AiAssistant::Assistant::PromptBuilder::MAX_REPLAYED_IMAGES
      allow(context.uploads).to receive(:all).and_return(Array.new(limit + 1) { |index| upload(token: "upload:#{index + 1}") })

      expect(render).to include("newest messages only, at most #{limit}")
    end

    it "explains the same once the images pass the replay size cap" do
      half = AiAssistant::Assistant::PromptBuilder::MAX_REPLAYED_BYTES / 2
      allow(context.uploads).to receive(:all).and_return(Array.new(3) { |index| upload(token: "upload:#{index + 1}", byte_size: half) })

      expect(render).to include("newest messages only")
    end

    it "does not mention the replay cap below it" do
      attach_image("shop.png")

      expect(render).not_to include("newest messages only")
    end

    it "never lists another tenant's attachments" do
      other = create(:customer)
      other_conversation = create(:ai_assistant_conversation, customer: other)
      message = create(:ai_assistant_message, conversation: other_conversation, customer: other)
      Current.set(customer: other) do
        message.images.attach(io: StringIO.new("\x89PNG\r\n\x1A\n"), filename: "theirs.png", content_type: "image/png")
      end
      attach_image("ours.png")

      expect(render).to include("ours.png").and(satisfy { |content| !content.include?("theirs.png") })
    end
  end
end
