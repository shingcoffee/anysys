# frozen_string_literal: true

module PageShortcuts
  # Public, empty failure response. No tenant/session landing callbacks: an
  # unavailable explicit root must remain 404 for anonymous and signed-in users.
  class UnavailableController < ActionController::Base
    def show
      head :not_found
    end
  end
end
