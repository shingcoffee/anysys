# frozen_string_literal: true

class HelpMessageBubbleComponent < ApplicationComponent
  def initialize(message:, viewer:)
    @message = message
    @viewer = viewer
  end

  attr_reader :message, :viewer

  def mine?
    message.user_id == viewer.id
  end

  def author_label
    if mine?
      I18n.t("chrome.help_menu.thread.you")
    elsif message.owner_author?
      I18n.t("chrome.help_menu.thread.platform")
    else
      message.user&.display_name
    end
  end

  def article_classes
    alignment = mine? ? "items-end" : "items-start"
    "flex flex-col gap-1 #{alignment}"
  end

  def bubble_classes
    if mine?
      "w-fit max-w-[min(85%,28rem)] rounded-2xl rounded-br-md bg-accent px-3.5 py-2 text-sm leading-6 text-white"
    else
      "w-fit max-w-[min(85%,28rem)] rounded-2xl rounded-bl-md bg-canvas px-3.5 py-2 text-sm leading-6 text-text-primary ring-1 ring-border-subtle"
    end
  end

  def timestamp_label
    I18n.l(message.created_at, format: :short)
  end

  def image_frame_classes
    border = mine? ? "border-white/20" : "border-border-subtle"
    "block overflow-hidden rounded-lg border #{border} bg-canvas/40"
  end
end
