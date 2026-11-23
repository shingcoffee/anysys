# frozen_string_literal: true

Rails.application.config.to_prepare do
  helper = Admin::Maintenance::PlatformPathHelper
  helper.install_if_needed!
  overrides = helper::Overrides

  url_helpers = Rails.application.routes.url_helpers
  unless url_helpers.ancestors.include?(overrides)
    url_helpers.prepend(overrides)
  end

  unless ApplicationController.ancestors.include?(helper)
    ApplicationController.prepend(helper)
  end
end
