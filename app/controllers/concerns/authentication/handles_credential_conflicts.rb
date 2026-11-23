# frozen_string_literal: true

module Authentication
  # CredentialLifecycle rejects stale snapshots instead of overwriting a newer
  # credential. Cover auth, admin and member mutation paths through their common
  # controller, without converting unrelated optimistic-lock errors.
  module HandlesCredentialConflicts
    extend ActiveSupport::Concern
    include Authentication::NoStore

    included do
      rescue_from ActiveRecord::StaleObjectError, with: :render_credential_conflict
    end

    private

    def render_credential_conflict(error)
      raise error unless error.record.is_a?(Authentication::User)

      no_store!
      # Exception handling runs after SetLocale's around_action unwinds.
      message = t("auth.errors.credentials_changed", locale: current_locale)
      respond_to do |format|
        format.json { render json: { error: "stale_credentials", message: message }, status: :conflict }
        format.any { render plain: message, status: :conflict }
      end
    end
  end
end
