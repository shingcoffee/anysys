# frozen_string_literal: true

# Register access-point providers. Order influences UI ordering.
Rails.application.config.after_initialize do
  AccessPoints::Registry.install_default_providers!
end
