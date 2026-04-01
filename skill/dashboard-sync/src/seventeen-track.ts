/**
 * seventeen-track.ts
 * 17track.net API integration for live shipment status.
 *
 * API docs: https://api.17track.net/
 * Get API key: https://user.17track.net/en/user/developer/api
 */

import { ShipmentStatus } from './orders-store';

const BASE_URL = 'https://api.17track.net';

// 17track status code mapping → our ShipmentStatus
const STATUS_MAP: Record<number, ShipmentStatus> = {
  0:  'unknown',       // Not found / no info
  10: 'label_created', // Label created
  20: 'in_transit',    // In transit
  30: 'in_transit',    // Arrived at carrier facility
  40: 'in_transit',    // Departed from carrier facility
  50: 'out_for_delivery', // Out for delivery
  60: 'delivered',     // Delivered
  70: 'exception',      // Exception / Failed delivery
  80: 'exception',      // Returned
  90: 'exception',      // Discarded
};

export interface TrackerEvent {
  timestamp: string;
  location: string;
  description: string;
}

export interface TrackerResponse {
  tracking_number: string;
  status: ShipmentStatus;
  carrier: string;
  latest_checkpoint: string | null;
  shipped_at: string | null;
  delivered_at: string | null;
  events: TrackerEvent[];
}

/**
 * Normalize 17track status code to our ShipmentStatus.
 */
function normalizeStatus(code: number): ShipmentStatus {
  return STATUS_MAP[code] ?? 'unknown';
}

/**
 * Register tracking numbers with 17track.
 * Must be done before polling.
 */
export async function registerTrackingNumbers(
  apiKey: string,
  trackingNumbers: Array<{ number: string; carrier?: string }>,
): Promise<void> {
  if (trackingNumbers.length === 0) return;

  const response = await fetch(`${BASE_URL}/v2/register`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      '17token': apiKey,
    },
    body: JSON.stringify({
      data: trackingNumbers.map(t => ({
        number: t.number,
        carrier: t.carrier || 'unknown',
      })),
    }),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`17track register failed (${response.status}): ${text}`);
  }
}

/**
 * Poll 17track for multiple tracking numbers.
 * Returns enriched tracker data.
 */
export async function pollTrackingNumbers(
  apiKey: string,
  trackingNumbers: string[],
): Promise<TrackerResponse[]> {
  if (trackingNumbers.length === 0) return [];

  const response = await fetch(`${BASE_URL}/v2/getTrackings`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      '17token': apiKey,
    },
    body: JSON.stringify({
      data: trackingNumbers.map(number => ({ number })),
      page: 1,
      pageSize: trackingNumbers.length,
    }),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`17track poll failed (${response.status}): ${text}`);
  }

  const json = await response.json() as {
    data?: Array<{
      number: string;
      carrier?: string;
      status?: number;
      lastEvent?: string;
      lastLocation?: string;
      firstEvent?: string;
      firstLocation?: string;
      acceptLanguage?: string;
    }>;
    errno?: number;
    errmsg?: string;
  };

  if (json.errno) {
    throw new Error(`17track API error ${json.errno}: ${json.errmsg}`);
  }

  const results: TrackerResponse[] = [];

  for (const item of json.data || []) {
    const statusCode = item.status ?? 0;
    const normalizedStatus = normalizeStatus(statusCode);

    // Build latest checkpoint from last event
    const latestCheckpoint = item.lastEvent
      ? `${item.lastLocation ? `${item.lastLocation} — ` : ''}${item.lastEvent}`
      : null;

    // shipped_at from first event (earliest meaningful event)
    let shippedAt: string | null = null;
    if (item.firstEvent && item.firstLocation && statusCode >= 10) {
      // First event after label creation is effectively when it shipped
      shippedAt = item.firstEvent;
    }

    // delivered_at
    const deliveredAt = normalizedStatus === 'delivered' ? (item.lastEvent || new Date().toISOString()) : null;

    results.push({
      tracking_number: item.number,
      status: normalizedStatus,
      carrier: item.carrier || 'unknown',
      latest_checkpoint: latestCheckpoint,
      shipped_at: shippedAt,
      delivered_at: deliveredAt,
      events: [],
    });
  }

  return results;
}

/**
 * Convenience: poll a single shipment's tracking number and return normalized response.
 */
export async function pollSingleShipment(
  apiKey: string,
  trackingNumber: string,
  carrier?: string,
): Promise<TrackerResponse> {
  const results = await pollTrackingNumbers(apiKey, [trackingNumber]);

  if (results.length === 0) {
    return {
      tracking_number: trackingNumber,
      status: 'unknown',
      carrier: carrier || 'unknown',
      latest_checkpoint: null,
      shipped_at: null,
      delivered_at: null,
      events: [],
    };
  }

  return results[0];
}

/**
 * Normalize a carrier name to 17track's expected format.
 * Returns the 17track carrier code.
 */
export function normalizeCarrierForTracker(carrier: string): string {
  const map: Record<string, string> = {
    'ups': 'ups',
    'fedex': 'fedex',
    'dhl': 'dhl',
    'usps': 'usps',
    'royal mail': 'royalmail',
    'hermes': 'hermes',
    'dpd': 'dpd',
    'gls': 'gls',
    'tnt': 'tnt',
    'aramex': 'aramex',
    'yanwen': 'yanwen',
    'yunexpress': 'yunexpress',
    '4px': '4px',
    'singpost': 'singpost',
    'generic': '',
  };

  const lower = carrier.toLowerCase().replace(/[^a-z]/g, '');
  return map[lower] || '';
}
