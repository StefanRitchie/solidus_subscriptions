# frozen_string_literal: true

# The LineItem class is responsible for associating Line items to subscriptions.  # It tracks the following values:
#
# [Spree::LineItem] :spree_line_item The spree object which created this instance
#
# [SolidusSubscription::Subscription] :subscription The object responsible for
#   grouping all information needed to create new subscription orders together
#
# [Integer] :subscribable_id The id of the object to be added to new subscription
#   orders when they are placed
#
# [Integer] :quantity How many units of the subscribable should be included in
#   future orders
#
# [Integer] :interval How often subscription orders should be placed
#
# [Integer] :installments How many subscription orders should be placed
module SolidusSubscriptions
  class LineItem < ApplicationRecord
    include Interval

    belongs_to(
      :spree_line_item,
      class_name: '::Spree::LineItem',
      inverse_of: :subscription_line_items,
      optional: true,
    )
    has_one :order, through: :spree_line_item, class_name: '::Spree::Order'
    belongs_to(
      :subscription,
      class_name: 'SolidusSubscriptions::Subscription',
      inverse_of: :line_items,
      optional: true
    )

    validates :subscribable_id, presence: true
    validates :quantity, numericality: { greater_than: 0 }
    validates :interval_length, numericality: { greater_than: 0 }, unless: -> { subscription }

    after_create :track_creation_event
    after_update :track_update_event
    after_destroy :track_destroy_event

    def as_json(**options)
      options[:methods] ||= [:dummy_line_item]
      super(options)
    end

    # Get a placeholder line item for calculating the values of future
    # subscription orders. It is frozen and cannot be saved
    def dummy_line_item
      li = LineItemBuilder.new([self]).spree_line_items.first
      return unless li

      li.order = dummy_order
      li.validate
      li.freeze
    end

    private

    # Get a placeholder order for calculating the values of future
    # subscription orders. It is a frozen duplicate of the current order and
    # cannot be saved
    def dummy_order
      order = spree_line_item ? spree_line_item.order.dup : ::Spree::Order.create
      order.ship_address = subscription.shipping_address || subscription.user.ship_address if subscription
      order.bill_address = subscription.billing_address || subscription.user.bill_address if subscription

      order.freeze
    end

    def as_json_for_event
      as_json.with_indifferent_access.except(
        :dummy_line_item,
        :interval_units,
        :interval_length,
        :end_date,
        :spree_line_item_id,
      )
    end

    def track_creation_event
      return unless subscription

      subscription.events.create!(event_type: 'line_item_created', details: as_json_for_event)
    end

    def track_update_event
      return unless subscription

      subscription.events.create!(event_type: 'line_item_updated', details: as_json_for_event)
    end

    def track_destroy_event
      return unless subscription

      subscription.events.create!(event_type: 'line_item_destroyed', details: as_json_for_event)
    end
  end
end
