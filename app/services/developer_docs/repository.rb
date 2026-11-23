# frozen_string_literal: true

require "yaml"

# Loads allow-listed documentation pages for one locale and builds the sidebar,
# previous/next links, and rendered article. Slugs never become filesystem paths
# until they pass the configured catalog.
module DeveloperDocs
  class Repository
    Source = Data.define(:title, :summary, :body, :path)
    Page = Data.define(
      :slug, :title, :summary, :html, :headings, :groups, :current_group,
      :previous_page, :next_page, :query, :search_path
    )
    Group = Data.define(:key, :entries)
    Entry = Data.define(:slug, :title, :path, :active)
    Link = Data.define(:slug, :title, :path)
    Topic = Data.define(:slug, :title, :summary, :path) do
      def initialize(slug:, title:, summary:, path:)
        super(slug: slug.dup.freeze, title: title.dup.freeze,
              summary: summary.dup.freeze, path: path.dup.freeze)
      end
    end

    def initialize(customer_id:, locale: I18n.locale, catalog: Catalog,
                   content_root: Rails.root.join("doc/reference"), translation_scope: "developer_docs",
                   route_helper: :admin_maintenance_platform_developer_doc_path, route_options: {},
                   screenshot_root: nil, screenshot_labels: nil)
      @customer_id = customer_id
      @catalog = catalog
      @content_root = Pathname.new(content_root)
      @translation_scope = translation_scope
      @route_helper = route_helper
      @route_options = route_options
      @screenshot_root = screenshot_root
      @screenshot_labels = screenshot_labels
      @locale = @catalog::LOCALES.include?(locale.to_s) ? locale.to_s : "en"
      @sources = {}
    end

    def page(slug, query: nil, search_path: nil)
      slug = slug.to_s
      return nil unless @catalog.slug?(slug)

      source = source_for(slug)
      return nil unless source

      rendered = render_source(source)
      query = normalize_query(query)
      unfiltered_groups = groups(slug)
      previous_slug, next_slug = neighbors(slug)
      Page.new(
        slug: slug,
        title: source.title,
        summary: source.summary,
        html: rendered.html,
        headings: rendered.headings,
        groups: filter_groups(unfiltered_groups, query),
        current_group: unfiltered_groups.find { |group| group.entries.any?(&:active) },
        previous_page: previous_slug && link_for(previous_slug),
        next_page: next_slug && link_for(next_slug),
        query: query,
        search_path: search_path.presence || doc_path(slug, route_options: navigation_route_options)
      )
    end

    # Homepage topic cards. Independent of the contents search query.
    def hub_groups
      route_options = @route_options.except(:q, "q", :locale, "locale")
      @catalog.groups.filter_map do |group|
        entries = group[:pages].filter_map do |slug|
          next if slug == @catalog::HOME_SLUG

          source = source_for(slug)
          next unless source

          Topic.new(slug:, title: source.title, summary: source.summary,
                    path: doc_path(slug, route_options:))
        end
        next if entries.empty?

        Group.new(key: group[:key].dup.freeze, entries: entries.freeze)
      end.freeze
    end

    private

    def content_root
      @content_root
    end

    def source_for(slug)
      @sources[slug] ||= read_source(slug)
    end

    def read_source(slug)
      path = existing_path(slug, @locale) || existing_path(slug, "en")
      return nil unless path

      body, meta = split_front_matter(File.read(path, encoding: "UTF-8"))
      Source.new(
        title: meta["title"].to_s.strip.presence || slug,
        summary: meta["summary"].to_s.strip,
        body: body.to_s,
        path: path
      )
    end

    def existing_path(slug, locale)
      root = content_root.expand_path
      path = root.join(locale, "#{slug}.md").expand_path
      return nil unless path.to_s.start_with?(root.to_s + File::SEPARATOR)
      return nil unless path.file?

      path
    end

    def split_front_matter(raw)
      return [raw, {}] unless raw.match(/\A---\r?\n(.*?)\r?\n---\r?\n(.*)\z/m)

      meta = YAML.safe_load(Regexp.last_match(1), permitted_classes: [], aliases: false)
      meta = {} unless meta.is_a?(Hash)
      [Regexp.last_match(2), meta]
    end

    def render_source(source)
      image_labels = screenshot_labels
      key = [
        Renderer::CACHE_VERSION, Renderer::SCREENSHOT_POLICY_VERSION, @screenshot_root, image_labels,
        @catalog.name, @translation_scope, @route_helper, @route_options,
        @customer_id.to_s, @locale, source.path.to_s, File.mtime(source.path).to_r.to_s
      ]
      cached = Rails.cache.fetch(key) do
        result = Renderer.call(
          source.body,
          catalog: @catalog,
          link_resolver: method(:doc_path),
          labels: callout_labels,
          anchor_label: I18n.t("#{@translation_scope}.anchor", locale: @locale),
          screenshot_root: @screenshot_root,
          screenshot_labels: image_labels
        )
        { "html" => result.html.to_s, "headings" => result.headings.map { |heading| heading.stringify_keys } }
      end
      Renderer::Result.new(
        html: cached["html"].html_safe,
        headings: cached["headings"].map { |heading| heading.symbolize_keys }
      )
    end

    def callout_labels
      {
        "attention" => I18n.t("#{@translation_scope}.callouts.attention", locale: @locale),
        "note" => I18n.t("#{@translation_scope}.callouts.note", locale: @locale)
      }
    end

    def screenshot_labels
      @screenshot_labels
    end

    def groups(current_slug)
      route_options = navigation_route_options
      @catalog.groups.filter_map do |group|
        entries = group[:pages].filter_map do |slug|
          source = source_for(slug)
          next unless source

          Entry.new(slug: slug, title: source.title, path: doc_path(slug, route_options:), active: slug == current_slug)
        end
        next if entries.empty?

        Group.new(key: group[:key], entries: entries)
      end
    end

    def filter_groups(groups, query)
      return groups if query.blank?

      groups.filter_map do |group|
        entries = group.entries.select { |entry| matches?(source_for(entry.slug), query) }
        next if entries.empty?

        Group.new(key: group.key, entries: entries)
      end
    end

    def matches?(source, query)
      return true if query.blank?

      "#{source.title}\n#{source.summary}\n#{source.body}".downcase.include?(query.downcase)
    end

    def neighbors(slug)
      existing = @catalog.slugs.select { |candidate| source_for(candidate) }
      index = existing.index(slug)
      return [nil, nil] unless index

      previous = index.positive? ? existing[index - 1] : nil
      [previous, existing[index + 1]]
    end

    def link_for(slug)
      Link.new(slug: slug, title: source_for(slug).title, path: doc_path(slug, route_options: navigation_route_options))
    end

    def navigation_route_options
      @route_options.except(:q, "q")
    end

    def doc_path(slug, route_options: @route_options)
      Rails.application.routes.url_helpers.public_send(@route_helper, @customer_id, slug, **route_options)
    end

    def normalize_query(query)
      query.to_s.strip.first(80)
    end
  end
end
