# frozen_string_literal: true

module AccessPoints
  class Catalog
    attr_reader :customer_id

    def self.for(customer_id:)
      Current.access_points_catalog ||= new(customer_id: customer_id)
    end

    def initialize(customer_id:)
      @customer_id = customer_id
    end

    def groups
      @groups ||= compute_groups
    end

    def find(subject_type:, subject_key: nil, subject_id: nil)
      all_descriptors.find do |d|
        d.subject_type == subject_type &&
          d.subject_key == subject_key &&
          d.subject_id == subject_id
      end
    end

    private

    def compute_groups
      by_group = Hash.new { |h, k| h[k] = [] }
      labels   = {}

      Registry.applicable_for(customer_id: customer_id).each do |p|
        labels[p.group_key] ||= p.group_label
        p.call(customer_id: customer_id).each do |d|
          by_group[d.group_key] << d
          labels[d.group_key] ||= p.label_for_group(d.group_key)
        end
      end

      by_group.map do |key, descs|
        { key: key, label: labels[key].presence || key.titleize, descriptors: descs }
      end
    end

    def all_descriptors
      groups.flat_map { |g| g[:descriptors] }
    end
  end
end
