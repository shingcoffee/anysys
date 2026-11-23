# frozen_string_literal: true

module Admin
  module Modules
    module AiAssistant
      # Admin-only enqueue for a dictate-widget audio clip. Validates + attaches
      # via EnqueueTranscription and returns 202; Whisper itself never runs on
      # this thread. Tenant comes from current_customer (URL + TenantContext) —
      # a client-supplied customer_id is ignored.
      #
      # Any DictateFieldComponent on any admin page posts here, so the clip's
      # destination is whatever the mounted widget declares (see
      # ::SpeechToText::TranscriptionEnqueueing).
      #
      # Authorization: RouteAuthorization gates /:cid/admin/* for admin/owner.
      class TranscriptionsController < ApplicationController
        include ::SpeechToText::TranscriptionEnqueueing

        dashboard_menu_item :modules
      end
    end
  end
end
