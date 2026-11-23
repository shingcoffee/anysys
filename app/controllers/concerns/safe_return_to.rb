# frozen_string_literal: true

# Allows mutating endpoints to redirect back to a same-app relative path
# supplied as `return_to` (e.g. an admin pages list or publishing slide-over).
# Rejects protocol-relative and absolute URLs to avoid open redirects, and
# requires the current tenant prefix so a crafted path cannot send the admin
# to another customer's admin URL (mirrors Authentication::SafeReturnPath).
module SafeReturnTo
  extend ActiveSupport::Concern

  private

  def safe_return_to
    path = params[:return_to].to_s
    return if path.blank?
    # Same allow-list as Authentication::SafeReturnPath: a leading slash is not
    # enough — `//host` is protocol-relative, and `/\host` is treated as a
    # protocol-relative URL by some clients (IE / older WebViews).
    return unless path.start_with?("/")
    return if path.start_with?("//", "/\\")
    return if path.include?("://")
    return if path.include?("..")

    cid = current_customer_id.to_s
    return if cid.blank?
    return unless path == "/#{cid}" || path.start_with?("/#{cid}/")

    path
  end
end
