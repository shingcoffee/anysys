# lib/tasks/flowchart_regenerate_activities.rake
namespace :flowcharts do
  desc "Regenerate stored Trailblazer activity Ruby for all flowcharts " \
       "(or CUSTOMER_ID=...). DRY_RUN=1 generates without persisting."
  task regenerate_activities: :environment do
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV["DRY_RUN"])
    scope = Flowchart.unscoped
    scope = scope.where(customer_id: ENV["CUSTOMER_ID"]) if ENV["CUSTOMER_ID"].present?

    failures = []
    succeeded = 0
    total = 0

    puts "flowcharts:regenerate_activities " \
         "dry_run=#{dry_run ? 1 : 0} " \
         "customer_id=#{ENV['CUSTOMER_ID'].presence || 'ALL'}"

    scope.find_each do |flowchart|
      total += 1
      activity = ActivityGenerator.new(flowchart).generate
      flowchart.update_column(:activity, activity) unless dry_run
      succeeded += 1
      puts "ok flowchart_id=#{flowchart.id}"
    rescue ActivityGenerator::Error => e
      failures << [flowchart.id, e.message]
      puts "fail flowchart_id=#{flowchart.id} error=#{e.message}"
    end

    puts "summary total=#{total} succeeded=#{succeeded} failed=#{failures.size}"
    failures.each do |flowchart_id, message|
      puts "  flowchart_id=#{flowchart_id} error=#{message}"
    end

    abort "#{failures.size} flowcharts failed regeneration" if failures.any?
  end
end
