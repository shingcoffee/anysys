# frozen_string_literal: true

# Destructive backfill. Reads each version's raw snapshot/configuration column
# one last time, stores it in the content-addressed table (dedup), and sets
# content_id. Ensures every parent has a current_version_id (latest version, or
# a freshly built v1 for parents that never had one — notably bridge entities,
# previously excluded from versioning). Then drops the payload columns, Entity's
# body columns, and Flowchart/Page's configuration column.
#
# All reads use raw SQL so the new Versionable after_save auto-commit and the
# head-loading after_find never fire during the migration.
class MigrateVersionsToContentStore < ActiveRecord::Migration[8.1]
  RESOURCES = [
    { versions: "entity_versions",    parent: "entities",   fk: "entity_id",
      content_model: "EntityDefinitionContent",      version_model: "EntityVersion",
      payload_col: "snapshot" },
    { versions: "flowchart_versions", parent: "flowcharts", fk: "flowchart_id",
      content_model: "FlowchartConfigurationContent", version_model: "FlowchartVersion",
      payload_col: "configuration" },
    { versions: "page_versions",      parent: "pages",      fk: "page_id",
      content_model: "PageConfigurationContent",      version_model: "PageVersion",
      payload_col: "configuration" }
  ].freeze

  ENTITY_BODY_COLUMNS = %i[
    property_schema default_properties associations attribute_groups
    extendable_models icon color description referenced_template
  ].freeze

  def up
    RESOURCES.each do |r|
      content_model = r[:content_model].constantize
      version_model = r[:version_model].constantize

      say_with_time "Backfilling #{r[:content_model]} from #{r[:versions]}" do
        count = 0
        select_all("SELECT id, customer_id, #{r[:payload_col]} AS payload FROM #{r[:versions]}").each do |row|
          content = content_model.store!(customer_id: row["customer_id"], payload: parse(row["payload"]))
          execute("UPDATE #{r[:versions]} SET content_id = #{content.id} WHERE id = #{row['id'].to_i}")
          count += 1
        end
        count
      end

      # Relax the legacy payload column's NOT NULL so v1 heads (built via the new
      # model, which no longer writes it) can be inserted before it is dropped.
      change_column_null r[:versions].to_sym, r[:payload_col].to_sym, true

      # Give every parent a head: point at its latest version, or build a v1 from
      # its live columns if it has none (bridge entities etc.). Done per-parent in
      # Ruby — a correlated UPDATE subquery is unreliable under SQLite here.
      backfill_heads(r, content_model, version_model)

      change_column_null r[:versions].to_sym, :content_id, false
      remove_column r[:versions].to_sym, r[:payload_col].to_sym
    end

    remove_column :flowcharts, :configuration
    remove_column :pages,      :configuration
    ENTITY_BODY_COLUMNS.each { |col| remove_column :entities, col }

    # The remove_column calls above rebuild the parent tables on SQLite, which
    # can null the current_version_id FK that backfill_heads just set. Re-assert
    # every headless parent to its latest version so heads survive the rebuild.
    RESOURCES.each do |r|
      execute(<<~SQL.squish)
        UPDATE #{r[:parent]} SET current_version_id = (
          SELECT v.id FROM #{r[:versions]} v
          WHERE v.#{r[:fk]} = #{r[:parent]}.id
          ORDER BY v.version_number DESC, v.id DESC LIMIT 1
        ) WHERE current_version_id IS NULL
          AND EXISTS (SELECT 1 FROM #{r[:versions]} v WHERE v.#{r[:fk]} = #{r[:parent]}.id)
      SQL
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  # Assign a head to every parent lacking one: point at the latest existing
  # version, else build a v1 (content + version) from its live columns. Model-
  # free reads so no parent callbacks fire.
  def backfill_heads(resource, content_model, version_model)
    say_with_time "Assigning heads for #{resource[:parent]}" do
      count = 0
      rows = select_all("SELECT p.* FROM #{resource[:parent]} p WHERE p.current_version_id IS NULL")

      rows.each do |row|
        pid = row["id"].to_i
        latest = select_value(
          "SELECT id FROM #{resource[:versions]} WHERE #{resource[:fk]} = #{pid} ORDER BY version_number DESC LIMIT 1"
        )

        version_id =
          latest || begin
            content = content_model.store!(customer_id: row["customer_id"], payload: head_payload_for(resource, row))
            # Raw INSERT (not version_model.create!) so replaying this historical
            # migration never loads the evolving app model — e.g. Entity's later
            # `enum :category` would fail here because that column does not exist
            # yet at this point in the migration timeline.
            execute(
              "INSERT INTO #{resource[:versions]} " \
              "(#{resource[:fk]}, customer_id, version_number, description, content_id, created_at, updated_at) " \
              "VALUES (#{pid}, #{quote(row['customer_id'])}, 1, 'Initial version', #{content.id.to_i}, " \
              "CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
            )
            select_value(
              "SELECT id FROM #{resource[:versions]} WHERE #{resource[:fk]} = #{pid} ORDER BY id DESC LIMIT 1"
            )
          end

        execute("UPDATE #{resource[:parent]} SET current_version_id = #{version_id.to_i} WHERE id = #{pid}")
        count += 1
      end
      count
    end
  end

  # The definition payload built from a parent's live columns.
  def head_payload_for(resource, row)
    if resource[:parent] == "entities"
      {
        "icon"                => row["icon"],
        "color"               => row["color"],
        "description"         => row["description"],
        "property_schema"     => parse(row["property_schema"], []),
        "default_properties"  => parse(row["default_properties"], {}),
        "associations"        => parse(row["associations"], []),
        "attribute_groups"    => parse(row["attribute_groups"], []),
        "extendable_models"   => parse(row["extendable_models"], []),
        "referenced_template" => row["referenced_template"]
      }
    else
      parse(row["configuration"], {})
    end
  end

  def parse(str, fallback = {})
    return fallback if str.nil? || (str.respond_to?(:empty?) && str.empty?)
    return str unless str.is_a?(String)
    JSON.parse(str)
  rescue JSON::ParserError
    fallback
  end
end
