# frozen_string_literal: true

# Uses the shared documentation reader with customer-only sources and links.
module CustomerDocs
  class Repository < DeveloperDocs::Repository
    Guide = Data.define(:slug, :title, :summary, :path) do
      def initialize(slug:, title:, summary:, path:)
        super(slug: slug.dup.freeze, title: title.dup.freeze,
              summary: summary.dup.freeze, path: path.dup.freeze)
      end
    end

    def initialize(customer_id:, locale: I18n.locale, screenshot_root: DeveloperDocs::Renderer::SCREENSHOT_ROOT, **options)
      super(
        customer_id:, locale:, catalog: Catalog,
        content_root: Rails.root.join("doc/customer"), translation_scope: "customer_docs",
        route_helper: :admin_help_doc_path, screenshot_root:, **options
      )
    end

    # Metadata is request-local, never taken from the rendered article cache or
    # filtered by the contents query. A new request sees front-matter edits.
    def guide_groups
      route_options = @route_options.except(:q, "q", :locale, "locale").merge(locale: @locale)
      @catalog.groups.filter_map do |group|
        entries = group[:pages].filter_map do |slug|
          next if slug == Catalog::HOME_SLUG

          source = source_for(slug)
          next unless source

          Guide.new(slug:, title: source.title, summary: source.summary,
                    path: doc_path(slug, route_options:))
        end
        next if entries.empty?

        Group.new(key: group[:key].dup.freeze, entries: entries.freeze)
      end.freeze
    end

    private

    def screenshot_labels
      return super if @screenshot_labels || @screenshot_root.nil?

      {
        full_size: I18n.t("customer_docs.screenshots.full_size", locale: @locale),
        open: I18n.t("customer_docs.screenshots.open", caption: "%{caption}", locale: @locale)
      }
    end
  end
end
