# frozen_string_literal: true

module Captcha
  class ChallengeComponent < ViewComponent::Base
    def initialize(return_to:, configured:, fail_closed:, captcha_failed: false)
      @return_to = return_to
      @configured = configured
      @fail_closed = fail_closed
      @captcha_failed = captcha_failed
    end

    def form_url = helpers.captcha_challenge_path
  end
end
