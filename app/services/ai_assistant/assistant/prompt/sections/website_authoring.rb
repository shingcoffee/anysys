# frozen_string_literal: true

module AiAssistant
  module Assistant
    module Prompt
      module Sections
        class WebsiteAuthoring < Section
          heads "How to build website pages"
          document "website_authoring"

          private

          def body
            return nil unless context.website_enabled?

            document.gsub("{max_pages}", Websites::Assistant::Extraction::MAX_PAGES.to_s)
          end
        end
      end
    end
  end
end
