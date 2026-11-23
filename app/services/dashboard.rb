# frozen_string_literal: true

module Dashboard
  Link = Data.define(:label, :href)
  Metric = Data.define(:key, :label, :value, :sub_label, :icon, :href)
  ModuleCard = Data.define(:key, :name, :description, :primary, :secondaries, :links, :section) do
    def initialize(key:, name:, description:, primary:, secondaries:, links: nil, section: nil)
      super
    end
  end
  SetupItem = Data.define(:key, :label, :done, :href)
  RecentItem = Data.define(:name, :href, :badge, :updated_at)
  Action = Data.define(:key, :label, :description, :path, :icon)
end
