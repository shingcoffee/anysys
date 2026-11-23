# frozen_string_literal: true

module PageShortcutsHelper
  # PublicPath returns application-relative paths. Keep mounted deployments on
  # the same SCRIPT_NAME without teaching the host/tenant service about Rack.
  def page_shortcuts_mounted_path(path)
    return path if path.blank? || !path.start_with?("/")

    "#{request.script_name.to_s.chomp('/')}#{path}"
  end
end
