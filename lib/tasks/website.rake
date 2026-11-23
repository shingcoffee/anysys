# frozen_string_literal: true

namespace :website do
  namespace :catalog do
    desc "Insert any new platform website layouts and skeletons from code seeds"
    task sync: :environment do
      Websites::Catalog.sync!
      puts "Website catalog synced: #{WebsiteLayout.count} layouts, #{WebsiteSkeleton.count} skeletons"
    end

    desc "Overwrite platform website layouts and skeletons with their code seeds"
    task refresh: :environment do
      Websites::Catalog.refresh!
      puts "Website catalog refreshed: #{WebsiteLayout.count} layouts, #{WebsiteSkeleton.count} skeletons"
    end
  end
end
