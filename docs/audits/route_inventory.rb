# frozen_string_literal: true

# Read-only text reconciliation. Never boots Rails, evaluates route DSL/source,
# queries a database, runs generated code, or writes a file.
# Input: the unmodified stdout of `bundle exec rails routes`.
# Output: JSON summary (default), expanded CSV (--csv), or compact matrix
# (--matrix). Matrix verb sets are lossless: GET|HEAD denotes both tuples.
# Optional --runtime-evidence=CSV grants only explicitly recorded tested verbs.
# Stable R IDs retain the original non-test inventory; T IDs are test-only.
require "csv"
require "json"
require "set"

REPORTS = {
  "core" => "2026-10-11-core-audit.md",
  "auth" => "2026-10-11-auth-audit.md",
  "email_sms" => "2026-10-11-email-sms-audit.md",
  "payments_captcha" => "2026-10-11-payments-audit.md",
  "website_ai_support" => "2026-10-11-website-ai-support-audit.md",
  "billing" => "2026-10-11-route-audit-manifest.md",
  "supplement" => "2026-10-11-route-audit-manifest.md"
}.freeze
INDEX = {}
runtime_evidence_path = ARGV.grep(/\A--runtime-evidence=/).first&.split("=", 2)&.last
runtime_claims = Hash.new { |hash, key| hash[key] = [] }
if runtime_evidence_path
  CSV.read(runtime_evidence_path, headers: true).each do |claim|
    claim.fetch("route_ids").split.each do |route_id|
      claim.fetch("verbs").split("|").each do |verb|
        runtime_claims[[route_id, verb]] << claim.to_h
      end
    end
  end
end

# The checked-in matrix is independently usable after a harness's temporary
# inspector stdout has expired. Expand every stored verb into a separate tuple.
if (matrix = ARGV.grep(/\A--expand-matrix=/).first)
  source = CSV.read(matrix.split("=", 2).last, headers: true)
  CSV($stdout) do |out|
    out << %w[route_id verb path controller action evidence_group status]
    source.each do |record|
      controller, action = record.fetch("controller_action").split("#", 2)
      record.fetch("verbs").split("|").each do |verb|
        route_id = record.fetch("route_id")[/\A([RT]\d{3})(?:-[A-Z+]+)?\z/, 1] or abort "Invalid matrix record ID"
        out << ["#{route_id}-#{verb}", verb, record.fetch("path"), controller, action,
                record.fetch("evidence_group"), record.fetch("status")]
      end
    end
  end
  exit
end

def register(group, controller, actions)
  actions.split.each { |action| INDEX[[controller, action]] ||= group }
end

# These are action indexes, not namespace-wide assertions of inspection.
# Original reports are retained as historical evidence; current-state findings
# and supplementary chains are reconciled in the manifest.
{
  "core" => {
    "admin/entity_definitions" => "index", "admin/domains" => "index show", "admin/entities" => "show",
    "admin/entity_entries" => "index show destroy batch_destroy", "admin/entity_index_settings" => "update",
    "admin/entity_pages" => "index", "admin/pages" => "index show batch_update",
    "admin/modules" => "index", "admin/module_entries" => "show", "admin/module_howtos" => "show",
    "admin/settings" => "show", "admin/module_configs" => "show update", "admin/search" => "index",
    "admin/maintenances" => "show", "admin/maintenance/customer_profiles" => "show edit update",
    "admin/maintenance/constants" => "index show new create edit update destroy",
    "admin/maintenance/constant_copies" => "show", "admin/maintenance/shared_resource_overrides" => "destroy",
    "admin/maintenance/entities" => "index show new create edit update destroy trash empty_trash template_fields base_model_fields",
    "admin/maintenance/entity_restorations" => "update", "admin/maintenance/entity_copies" => "show",
    "admin/maintenance/entity_template_previews" => "show",
    "admin/maintenance/entity_versions" => "index show create edit destroy default",
    "admin/maintenance/modules" => "index", "admin/maintenance/module_enablements" => "create destroy",
    "admin/maintenance/module_sub_toggles" => "update", "admin/maintenance/module_owner_configurations" => "update",
    "admin/maintenance/platform/customers" => "index show new create edit update destroy trash empty_trash",
    "admin/maintenance/platform/customer_restorations" => "update",
    "admin/maintenance/platform/module_settings" => "index show update configuration developer",
    "admin/maintenance/platform/industry_templates" => "index show edit update",
    "admin/maintenance/platform/industry_template_assignments" => "create destroy",
    "admin/maintenance/platform/industry_template_cards" => "show",
    "admin/maintenance/platform/industry_template_default_seeds" => "create destroy",
    "admin/maintenance/platform/industry_template_new_template_seeds" => "create",
    "admin/maintenance/platform/developer_docs" => "index show",
    "admin/maintenance/platform/customer_contexts" => "update destroy search"
  },
  "auth" => {
    "authentication/sessions" => "new create destroy", "authentication/passwords" => "new create edit update",
    "authentication/confirmations" => "new create show", "authentication/customer_registrations" => "new create check_email resend confirm",
    "authentication/registrations" => "new create edit update", "authentication/sign_in_links" => "create check_email show",
    "authentication/mfa_setups" => "show create", "authentication/mfa_sessions" => "show create",
    "authentication/mfas" => "destroy", "authentication/mfa_recoveries" => "new create consume",
    "oauth/authorizations" => "new create destroy show", "oauth/tokens" => "create revoke introspect",
    "oauth/userinfo" => "show", "oauth/discovery" => "show",
    "admin/modules/authentication/users" => "index show new create edit update",
    "admin/modules/authentication/user_activations" => "create destroy",
    "admin/modules/authentication/user_mfa_resets" => "create",
    "admin/modules/authentication/user_trusted_devices" => "destroy", "admin/modules/authentication/events" => "index",
    "admin/settings/modules/authentication/roles" => "index show new create edit update destroy",
    "admin/settings/modules/authentication/role_grants" => "show update",
    "admin/settings/modules/authentication/user_role_assignments" => "index create destroy",
    "admin/settings/modules/authentication/sign_up" => "show update", "admin/settings/modules/authentication/forget_password" => "show update",
    "admin/settings/members" => "show update", "admin/settings/member_sources" => "show update",
    "admin/settings/member_surfaces" => "show update", "member/dashboards" => "show",
    "member/profiles" => "show edit update", "member/securities" => "show", "member/mfa" => "setup destroy",
    "member/trusted_devices" => "destroy", "member/surfaces" => "index show", "member/pages" => "show"
  },
  "email_sms" => {
    "emails/webhooks" => "create", "sms/webhooks" => "create", "emails/tracking" => "open click",
    "emails/unsubscribes" => "show create", "admin/modules/emails/dashboard" => "show",
    "admin/modules/emails/health" => "index", "admin/modules/emails/templates" => "index show new create edit update destroy status preview test_send duplicate",
    "admin/modules/emails/template_versions" => "index show create edit destroy default",
    "admin/modules/emails/attachments" => "create show", "admin/modules/emails/send_activities" => "index show new create edit update destroy",
    "admin/modules/emails/send_activity_deliveries" => "create", "admin/modules/emails/send_activity_cancellations" => "create",
    "admin/modules/emails/lists" => "index show new create edit update destroy preview", "admin/modules/emails/reports" => "index",
    "admin/modules/emails/deliverability" => "index", "admin/modules/emails/engagement" => "index",
    "admin/modules/emails/suppressions" => "index batch_unblock", "admin/settings/modules/emails/template_tokens" => "index new create edit update destroy",
    "admin/maintenance/platform/emails/credentials" => "index new create edit update delivery",
    "admin/maintenance/platform/sms/credentials" => "index new create edit update delivery",
    "admin/maintenance/platform/sms/templates" => "index new create edit update destroy",
    "admin/modules/sms/messages" => "index show", "admin/modules/sms/sends" => "create", "admin/modules/sms/opt_outs" => "index"
  },
  "payments_captcha" => {
    "payments/checkouts" => "start collect complete show create status", "payments/results" => "show", "payments/webhooks" => "create",
    "admin/modules/payments/transactions" => "index show", "admin/modules/payments/refunds" => "create",
    "admin/modules/payments/subscriptions" => "index show new create", "admin/modules/payments/subscription_cancellations" => "create",
    "admin/modules/payments/reconciliations" => "index show download", "admin/modules/payments/disputes" => "index",
    "admin/settings/modules/payments/merchant_accounts" => "index new create edit update test_connection",
    "admin/settings/modules/payments/default_gateways" => "update",
    "admin/maintenance/platform/payments/platform_gateways" => "index update",
    "admin/maintenance/platform/payments/webhook_events" => "index redrive",
    "member/payments/payment_methods" => "index new create destroy setup_intent",
    "member/payments/subscriptions" => "index show", "member/payments/subscription_cancellations" => "create",
    "captcha/challenges" => "show create", "admin/settings/modules/captcha/status" => "show",
    "admin/settings/modules/captcha/pages" => "update", "admin/maintenance/platform/captcha/settings" => "show edit update test_connection",
    "admin/maintenance/platform/captcha/surfaces" => "update", "admin/maintenance/platform/captcha/pages" => "index update"
  },
  "website_ai_support" => {
    "page_shortcuts/unavailable" => "show", "public_pages" => "show submit", "websites/pages" => "home show", "websites/assets" => "show",
    "admin/maintenance/page_shortcuts" => "index create update destroy", "admin/modules/website/pages" => "index new create edit update destroy preview reorder",
    "admin/modules/website/media" => "create", "admin/settings/modules/website/sites" => "show update",
    "admin/settings/modules/website/skeletons" => "create", "admin/maintenance/platform/website/skeletons" => "show edit update",
    "admin/maintenance/platform/website/layouts" => "index new create edit update", "admin/assistants" => "show", "admin/dashboards" => "show",
    "admin/modules/ai_assistant/conversations" => "index create update destroy archive",
    "admin/modules/ai_assistant/messages" => "create mentions undo stop regenerate", "admin/modules/ai_assistant/transcriptions" => "create",
    "admin/assistant/messages" => "index create", "admin/assistant/transcriptions" => "create show",
    "admin/maintenance/platform/ai_assistant/settings" => "show edit update test_connection",
    "admin/maintenance/platform/announcements" => "index show new create edit update destroy audience_preview",
    "admin/platform_announcement_reads" => "create", "admin/platform_announcement_dismissals" => "create", "admin/support_ticket_reads" => "create",
    "admin/support_tickets" => "show create", "admin/support_ticket_messages" => "create", "admin/help_emails" => "create",
    "admin/maintenance/platform/support_tickets" => "index show", "admin/maintenance/platform/support_ticket_messages" => "create",
    "admin/maintenance/platform/support_ticket_resolutions" => "create", "admin/help/docs" => "index show", "home" => "index"
  },
  "billing" => {
    "admin/settings/billing/subscriptions" => "show update plan_change_preview", "admin/settings/billing/plan_changes" => "destroy",
    "admin/settings/billing/cancellations" => "create destroy", "admin/settings/billing/coupon_redemptions" => "create",
    "admin/settings/billing/payment_methods" => "index create destroy make_default setup_intent authorization confirmation",
    "admin/settings/billing/invoices" => "index show download", "admin/settings/billing/invoice_payments" => "create",
    "admin/maintenance/platform/billing/plans" => "index show new create edit update destroy",
    "admin/maintenance/platform/billing/countable_items" => "show update", "admin/maintenance/platform/billing/coupons" => "index show new create edit update destroy",
    "admin/maintenance/platform/billing/subscriptions" => "index show", "admin/maintenance/platform/billing/cancellations" => "create",
    "admin/maintenance/platform/billing/invoices" => "index show mark_paid void retry", "admin/maintenance/platform/billing/settings" => "show edit update"
  },
  "supplement" => {
    "view_components_system_test" => "system_test_entrypoint",
    "locales" => "update", "rails/health" => "show", "turbo/native/navigation" => "recede resume refresh",
    "action_mailbox/ingresses/postmark/inbound_emails" => "create", "action_mailbox/ingresses/relay/inbound_emails" => "create",
    "action_mailbox/ingresses/sendgrid/inbound_emails" => "create", "action_mailbox/ingresses/mandrill/inbound_emails" => "create health_check",
    "action_mailbox/ingresses/mailgun/inbound_emails" => "create", "rails/conductor/action_mailbox/inbound_emails" => "index create new show",
    "rails/conductor/action_mailbox/inbound_emails/sources" => "new create", "rails/conductor/action_mailbox/reroutes" => "create",
    "rails/conductor/action_mailbox/incinerates" => "create", "active_storage/blobs/redirect" => "show", "active_storage/blobs/proxy" => "show",
    "active_storage/representations/redirect" => "show", "active_storage/representations/proxy" => "show",
    "active_storage/disk" => "show update", "active_storage/direct_uploads" => "create"
  }
}.each { |group, controllers| controllers.each { |controller, actions| register(group, controller, actions) } }

def exclusion(path, controller, action)
  return "maintenance_flowchart_builder" if path.match?(%r{/admin/maintenance/(?:platform/)?flowcharts(?:/|\(\.:format\)|$)})
  return "maintenance_page_builder" if path.match?(%r{/admin/maintenance/(?:platform/)?pages(?:/|\(\.:format\)|$)})
  return "builder_code_generators" if path.match?(%r{/admin/maintenance/platform/code_generators(?:/|\(\.:format\)|$)})
  return "entity_version_creates_builder_page" if controller == "admin/maintenance/entity_versions" && action == "page"
  return "builder_template_picker" if controller == "admin/maintenance/template_picker_cards"
  return "standalone_builder_template_preview" if controller == "admin/maintenance/template_previews"
  # Persisted-entity lookup/reference validation was inspected in core. Its
  # downstream transient Page authoring renderer is an excluded boundary.
  nil
end

input = ARGV.find { |arg| !arg.start_with?("--") } or abort "Usage: ruby docs/audits/route_inventory.rb ROUTES_STDOUT [--csv|--patch]"
application_sequence = 0
test_sequence = 0
entries = File.readlines(input, chomp: true).filter_map.with_index do |line, index|
  match = line.match(/^\s*(\S+)?\s+(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)(\|(?:GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS))*\s+(\/\S*)\s+(\S+)#(\w+)(.*)$/)
  next if index.zero? && line.include?("URI Pattern")
  abort "Unparsed route output line #{index + 1}: #{line}" unless match
  # Capture the entire verb token independently (the optional regexp group
  # retains only the final alternative for multi-verb routes).
  name, methods, path, target, constraints = line.strip.match(/^(?:(\S+)\s+)?((?:GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)(?:\|(?:GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS))*)\s+(\/\S*)\s+(\S+#\w+)(.*)$/).captures
  controller, action = target.split("#", 2)
  test_only = controller == "view_components_system_test" && action == "system_test_entrypoint"
  route_id = if test_only
    test_sequence += 1
    format("T%03d", test_sequence)
  else
    application_sequence += 1
    format("R%03d", application_sequence)
  end
  excluded = exclusion(path, controller, action)
  group = excluded ? "excluded" : INDEX[[controller, action]]
  constraints = constraints.strip
  if ["/", "/*shortcut_path"].include?(path)
    constraints = if controller == "home"
      "fallback_root"
    elsif controller == "page_shortcuts/unavailable"
      "PageShortcuts::Resolver.unavailable_root?"
    else
      "PageShortcuts::RouteConstraint.matches?(#{target})"
    end
  elsif %w[payments/webhooks sms/webhooks emails/webhooks].include?(controller)
    constraints = "request_time_provider_registry"
  end
  { sequence: index, route_id: route_id, test_only: test_only, name: name.to_s, methods: methods.split("|"), path: path,
    controller: controller, action: action, constraints: constraints,
    status: excluded ? "excluded" : (group ? "source_inspected" : "inventoried"),
    group: group || "unreviewed", exclusion: excluded.to_s }
end

rows = entries.flat_map do |entry|
  methods = entry[:methods]
  methods += ["HEAD"] if methods.include?("GET") && !methods.include?("HEAD")
  methods.map do |verb|
    claims = runtime_claims.fetch([entry[:route_id], verb], [])
    status = claims.any? && entry[:status] == "source_inspected" ? "runtime_verified" : entry[:status]
    entry.merge(verb: verb, status: status, runtime_evidence: claims,
                implicit_head: verb == "HEAD" && !entry[:methods].include?("HEAD"))
  end
end

eligible_keys = rows.select { |row| row[:status] != "excluded" && row[:group] != "unreviewed" }
                    .map { |row| [row[:route_id], row[:verb]] }.to_set
abort "Runtime evidence names an excluded/unknown route or unsupported verb" if (runtime_claims.keys.to_set - eligible_keys).any?

# Split a grouped GET/HEAD or PUT/PATCH cell only when evidence statuses differ.
# A GET pass must never promote HEAD; action coverage must not promote aliases.
matrix_rows = entries.flat_map do |entry|
  record_rows = rows.select { |row| row[:route_id] == entry[:route_id] }
  groups = record_rows.group_by { |row| row[:status] }
  groups.map do |status, group|
    verbs = group.map { |row| row[:verb] }
    id = groups.one? ? entry[:route_id] : "#{entry[:route_id]}-#{verbs.join('+')}"
    { "route_id" => id, "verbs" => verbs.join("|"), "path" => entry[:path],
      "controller_action" => "#{entry[:controller]}##{entry[:action]}",
      "evidence_group" => entry[:group], "status" => status }
  end
end

if (refresh = ARGV.grep(/\A--refresh-matrix=/).first)
  path = refresh.split("=", 2).last
  actual = CSV.read(path, headers: true)
  keys = %w[route_id verbs path controller_action evidence_group status]
  existing = actual.group_by { |record| record.fetch("route_id")[/\A([RT]\d{3})/, 1] }
  expected = matrix_rows.group_by { |record| record.fetch("route_id")[/\A([RT]\d{3})/, 1] }
  abort "Refresh cannot delete inventory records" unless (existing.keys - expected.keys).empty?
  puts "*** Begin Patch", "*** Update File: #{path}"
  expected.each do |id, records|
    next unless existing.key?(id)
    before = existing.fetch(id).map { |record| CSV.generate_line(keys.map { |key| record.fetch(key) }).chomp }
    after = records.map { |record| CSV.generate_line(keys.map { |key| record.fetch(key) }).chomp }
    next if before == after
    puts "@@"
    before.each { |line| puts "-#{line}" }
    after.each { |line| puts "+#{line}" }
  end
  added = expected.keys - existing.keys
  if added.any?
    puts "@@", " #{CSV.generate_line(actual[-1].fields).chomp}"
    added.each do |id|
      expected.fetch(id).each { |record| puts "+#{CSV.generate_line(keys.map { |key| record.fetch(key) }).chomp}" }
    end
  end
  puts "*** End Patch"
  exit
end

if (check = ARGV.grep(/\A--check-matrix=/).first)
  path = check.split("=", 2).last
  actual = CSV.read(path, headers: true).map(&:to_h)
  expand = lambda do |records|
    records.flat_map do |record|
      id = record.fetch("route_id")[/\A([RT]\d{3})(?:-[A-Z+]+)?\z/, 1]
      abort "Invalid matrix record ID" unless id
      record.fetch("verbs").split("|").map do |verb|
        [id, verb, record.fetch("path"), record.fetch("controller_action"),
         record.fetch("evidence_group"), record.fetch("status")]
      end
    end.sort
  end
  abort "Coverage matrix differs from inspector output/evidence" unless expand.call(actual) == expand.call(matrix_rows)
  puts "Coverage matrix matches all #{entries.size} inspector entries / #{rows.size} effective verb records."
  exit
end

if ARGV.include?("--matrix")
  first = ARGV.grep(/\A--from=/).first&.split("=")&.last&.to_i || 1
  last = ARGV.grep(/\A--to=/).first&.split("=")&.last&.to_i || entries.size
  CSV($stdout) do |out|
    out << %w[route_id verbs path controller_action evidence_group status] if first == 1
    ids = entries.select { |entry| entry[:sequence].between?(first, last) }.map { |entry| entry[:route_id] }.to_set
    matrix_rows.each do |record|
      next unless ids.include?(record.fetch("route_id")[/\A([RT]\d{3})/, 1])
      out << record.values
    end
  end
elsif ARGV.include?("--csv") || ARGV.include?("--patch")
  csv = CSV.generate do |out|
    out << %w[route_id verb path controller action route_name constraints status evidence_group exclusion implicit_head]
    rows.each do |row|
      out << ["#{row[:route_id]}-#{row[:verb]}", row[:verb], row[:path], row[:controller], row[:action],
              row[:name], row[:constraints], row[:status], row[:group], row[:exclusion], row[:implicit_head]]
    end
  end
  if ARGV.include?("--patch")
    puts "*** Begin Patch", "*** Add File: docs/audits/2026-10-11-route-coverage.csv"
    csv.each_line { |line| puts "+#{line.chomp}" }
    puts "*** End Patch"
  else
    print csv
  end
else
  summary = {
    inspector_entries: entries.size,
    explicit_verb_records: entries.sum { |entry| entry[:methods].size },
    effective_verb_records: rows.size,
    implicit_head_records: rows.count { |row| row[:implicit_head] },
    test_only_effective: rows.count { |row| row[:test_only] },
    by_effective_status: rows.group_by { |row| row[:status] }.transform_values(&:size),
    runtime_verified_by_group: rows.select { |row| row[:status] == "runtime_verified" }.group_by { |row| row[:group] }.transform_values(&:size),
    runtime_verified_explicit: rows.count { |row| row[:status] == "runtime_verified" && !row[:implicit_head] },
    runtime_verified_distinct_actions: rows.select { |row| row[:status] == "runtime_verified" }.map { |row| [row[:controller], row[:action]] }.uniq.size,
    eligible_explicit: entries.reject { |entry| entry[:status] == "excluded" }.sum { |entry| entry[:methods].size },
    excluded_explicit: entries.select { |entry| entry[:status] == "excluded" }.sum { |entry| entry[:methods].size },
    eligible_effective: rows.count { |row| row[:status] != "excluded" },
    excluded_effective: rows.count { |row| row[:status] == "excluded" },
    eligible_distinct_actions: rows.reject { |row| row[:status] == "excluded" }.map { |row| [row[:controller], row[:action]] }.uniq.size,
    by_group: entries.group_by { |entry| entry[:group] }.transform_values { |group| group.sum { |entry| entry[:methods].size } },
    by_group_effective: rows.group_by { |row| row[:group] }.transform_values(&:size),
    by_group_actions: entries.group_by { |entry| entry[:group] }.transform_values { |group| group.map { |entry| [entry[:controller], entry[:action]] }.uniq.size },
    by_exclusion: entries.select { |entry| entry[:status] == "excluded" }.group_by { |entry| entry[:exclusion] }.transform_values(&:size),
    by_exclusion_effective: rows.select { |row| row[:status] == "excluded" }.group_by { |row| row[:exclusion] }.transform_values(&:size),
    unreviewed: entries.select { |entry| entry[:status] == "inventoried" }.map { |entry| entry.slice(:sequence, :path, :controller, :action) },
    evidence: REPORTS
  }
  puts JSON.pretty_generate(summary)
end
