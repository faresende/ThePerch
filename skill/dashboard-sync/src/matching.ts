import { normalizeMerchantName } from './orders';
import type { OrderData, ReviewItemData, ShipmentData } from './types';

export interface OrderRecordCandidate {
  id: string;
  data: OrderData;
}

export interface ShipmentRecordCandidate {
  id: string;
  data: ShipmentData;
}

export interface ShipmentMatchResult {
  matched_order_id?: string;
  matched_shipment_id?: string;
  review_item?: ReviewItemData;
}

export function buildReviewItem(input: {
  type: ReviewItemData['type'];
  reason: string;
  suggested_action: string;
  confidence_score: number;
  related_order_id?: string;
  related_shipment_id?: string;
}): ReviewItemData {
  return {
    type: input.type,
    reason: input.reason,
    suggested_action: input.suggested_action,
    confidence_score: input.confidence_score,
    related_order_id: input.related_order_id,
    related_shipment_id: input.related_shipment_id,
  };
}

export function matchShipmentToOrder(input: {
  shipment: ShipmentData;
  existing_orders: OrderRecordCandidate[];
  existing_shipments: ShipmentRecordCandidate[];
}): ShipmentMatchResult {
  const trackingNumber = normalizeTracking(input.shipment.tracking_number);
  const matchedShipment = trackingNumber
    ? input.existing_shipments.find((shipment) => normalizeTracking(shipment.data.tracking_number) === trackingNumber)
    : undefined;

  if (matchedShipment) {
    return { matched_shipment_id: matchedShipment.id };
  }

  if (input.shipment.order_id) {
    const exactOrder = input.existing_orders.find((order) => order.id === input.shipment.order_id);
    if (exactOrder) {
      return { matched_order_id: exactOrder.id };
    }
  }

  const normalizedMerchant =
    input.shipment.normalized_merchant ||
    (input.shipment.merchant_name ? normalizeMerchantName(input.shipment.merchant_name) : '');
  const orderNumber = input.shipment.order_number?.trim();

  if (normalizedMerchant && orderNumber) {
    const exactMatches = input.existing_orders.filter(
      (order) =>
        order.data.normalized_merchant === normalizedMerchant &&
        order.data.order_number.trim() === orderNumber,
    );

    if (exactMatches.length === 1) {
      return { matched_order_id: exactMatches[0].id };
    }

    if (exactMatches.length > 1) {
      return {
        review_item: buildReviewItem({
          type: 'ambiguous_order_match',
          reason: `Multiple orders matched ${normalizedMerchant} ${orderNumber}.`,
          suggested_action: 'Review the candidate orders before linking this shipment.',
          confidence_score: 0.36,
          related_order_id: exactMatches[0].id,
        }),
      };
    }
  }

  if (normalizedMerchant && !orderNumber) {
    const merchantMatches = input.existing_orders.filter(
      (order) => order.data.normalized_merchant === normalizedMerchant,
    );

    if (merchantMatches.length > 1) {
      return {
        review_item: buildReviewItem({
          type: 'ambiguous_order_match',
          reason: `Shipment matched ${merchantMatches.length} orders for ${normalizedMerchant} but had no order number.`,
          suggested_action: 'Review matching orders and attach tracking manually.',
          confidence_score: 0.31,
          related_order_id: merchantMatches[0].id,
        }),
      };
    }
  }

  if (trackingNumber) {
    return {
      review_item: buildReviewItem({
        type: 'missing_order_for_tracking',
        reason: `Tracking ${trackingNumber} could not be linked to any known order.`,
        suggested_action: 'Create a standalone shipment and queue this for order review.',
        confidence_score: 0.58,
      }),
    };
  }

  return {
    review_item: buildReviewItem({
      type: 'missing_tracking_for_order',
      reason: 'Shipment-like event did not contain a usable tracking number.',
      suggested_action: 'Keep the commerce item detached until tracking is available.',
      confidence_score: 0.24,
    }),
  };
}

export function deriveOrderStatusFromShipments(shipments: ShipmentData[]): OrderData['status'] {
  if (shipments.length === 0) {
    return 'ordered';
  }

  const statuses = shipments.map((shipment) => shipment.status);

  if (statuses.some((status) => status === 'exception')) {
    return 'issue';
  }

  if (statuses.every((status) => status === 'delivered')) {
    return 'delivered';
  }

  const shippedLikeCount = statuses.filter((status) =>
    ['label_created', 'in_transit', 'out_for_delivery', 'delivered'].includes(status),
  ).length;
  const deliveredCount = statuses.filter((status) => status === 'delivered').length;

  if (deliveredCount > 0 && deliveredCount < shipments.length) {
    return 'shipped_partial';
  }

  if (shippedLikeCount > 0) {
    return 'shipped';
  }

  return 'processing';
}

function normalizeTracking(value?: string): string {
  return value?.trim().toUpperCase() || '';
}
