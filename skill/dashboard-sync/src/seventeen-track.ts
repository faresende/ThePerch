/**
 * seventeen-track.ts
 * 17track.net API integration for live shipment status.
 *
 * API docs: https://api.17track.net/
 * Get API key: https://user.17track.net/en/user/developer/api
 */

import { ShipmentStatus } from './orders-store';

// 17track renamed the API root from /v2 to /track/v2 (and current v2.2).
// Override via SEVENTEEN_TRACK_BASE_URL if 17track changes it again.
const BASE_URL = process.env.SEVENTEEN_TRACK_BASE_URL || 'https://api.17track.net/track/v2.2';

// 17track v2.2 status mapping. The API now returns a string status in
// latest_status.status (not a numeric code). Values observed in the wild:
//   NotFound, InfoReceived, InTransit, Expired, AvailableForPickup,
//   OutForDelivery, DeliveryFailure, Delivered, Exception, NotFoundAfter10Days
const STATUS_MAP: Record<string, ShipmentStatus> = {
  NotFound: 'unknown',
  InfoReceived: 'label_created',
  InTransit: 'in_transit',
  Expired: 'exception',
  AvailableForPickup: 'out_for_delivery',
  OutForDelivery: 'out_for_delivery',
  DeliveryFailure: 'exception',
  Delivered: 'delivered',
  Exception: 'exception',
  NotFoundAfter10Days: 'unknown',
};

// Legacy numeric-code map, kept so older callers (or legacy responses via
// SEVENTEEN_TRACK_BASE_URL override) still work if we ever hit them.
const LEGACY_CODE_MAP: Record<number, ShipmentStatus> = {
  0:  'unknown',
  10: 'label_created',
  20: 'in_transit',
  30: 'in_transit',
  40: 'in_transit',
  50: 'out_for_delivery',
  60: 'delivered',
  70: 'exception',
  80: 'exception',
  90: 'exception',
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
  /** Phase 1 ETA (2026-04-27): pulled from track_info.time_metrics.
   *  estimated_delivery_date. Null when 17track doesn't have one
   *  (some carriers don't surface it). Caller runs through
   *  resolveETAUpdate against the current shipment row. */
  eta_at: string | null;
  events: TrackerEvent[];
}

/**
 * Normalize 17track status (string or legacy numeric) to our ShipmentStatus.
 */
function normalizeStatus(raw: string | number | undefined): ShipmentStatus {
  if (raw === undefined || raw === null) return 'unknown';
  if (typeof raw === 'number') return LEGACY_CODE_MAP[raw] ?? 'unknown';
  return STATUS_MAP[raw] ?? 'unknown';
}

/**
 * Register tracking numbers with 17track v2.2.
 *
 * Endpoint: POST {BASE_URL}/register
 * Body: bare JSON array — [{number, carrier?}, ...]
 * Response: { code: 0, data: { accepted: [...], rejected: [{number, error: {code, message}}] } }
 *
 * 17track quietly accepts already-registered numbers (returns them under
 * `rejected` with a "number already exists" error). This function treats
 * that as success.
 */
export async function registerTrackingNumbers(
  apiKey: string,
  trackingNumbers: Array<{ number: string; carrier?: string }>,
): Promise<void> {
  if (trackingNumbers.length === 0) return;

  const response = await fetch(`${BASE_URL}/register`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      '17token': apiKey,
    },
    body: JSON.stringify(
      trackingNumbers.map(t => ({
        number: t.number,
        ...(t.carrier ? { carrier: t.carrier } : {}),
      })),
    ),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`17track register failed (${response.status}): ${text}`);
  }
}

/**
 * Poll 17track v2.2 for multiple tracking numbers.
 *
 * Endpoint: POST {BASE_URL}/gettrackinfo
 * Body: bare JSON array — [{number, carrier?}, ...]
 * Response shape (v2.2):
 *   {
 *     code: 0,
 *     data: {
 *       accepted: [{
 *         number,
 *         track_info: {
 *           latest_status: { status, sub_status? },
 *           latest_event: { time_iso, description?, location? },
 *           time_metrics: { estimated_delivery_date? },
 *           shipping_info: { shipper_address?, recipient_address? },
 *           tracking: { providers: [{ provider: { name } }] }
 *         }
 *       }],
 *       rejected: [...]
 *     }
 *   }
 */
export async function pollTrackingNumbers(
  apiKey: string,
  trackingNumbers: string[],
): Promise<TrackerResponse[]> {
  if (trackingNumbers.length === 0) return [];

  const response = await fetch(`${BASE_URL}/gettrackinfo`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      '17token': apiKey,
    },
    body: JSON.stringify(trackingNumbers.map(number => ({ number }))),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`17track poll failed (${response.status}): ${text}`);
  }

  const json = await response.json() as {
    code?: number;
    message?: string;
    data?: {
      accepted?: Array<{
        number: string;
        track_info?: {
          latest_status?: { status?: string; sub_status?: string };
          latest_event?: { time_iso?: string; description?: string; location?: string };
          time_metrics?: { estimated_delivery_date?: string };
          tracking?: {
            providers?: Array<{ provider?: { name?: string } }>;
          };
        };
      }>;
      rejected?: Array<{ number: string; error?: { code: number; message: string } }>;
    };
    // Legacy v2 error shape retained for back-compat.
    errno?: number;
    errmsg?: string;
  };

  // v2.2 top-level code: 0 = ok, anything else = overall failure.
  if (typeof json.code === 'number' && json.code !== 0 && json.code !== -2) {
    throw new Error(`17track API error ${json.code}: ${json.message ?? 'no message'}`);
  }
  if (json.errno) {
    throw new Error(`17track API error ${json.errno}: ${json.errmsg}`);
  }

  const results: TrackerResponse[] = [];

  for (const item of json.data?.accepted ?? []) {
    const info = item.track_info ?? {};
    const status = normalizeStatus(info.latest_status?.status);
    const ev = info.latest_event ?? {};

    const latestCheckpoint = ev.description
      ? `${ev.location ? `${ev.location} — ` : ''}${ev.description}`
      : null;

    const deliveredAt = status === 'delivered'
      ? (ev.time_iso || new Date().toISOString())
      : null;

    const carrier = info.tracking?.providers?.[0]?.provider?.name ?? 'unknown';

    // Phase 1 ETA: pull estimated_delivery_date from time_metrics.
    // 17track returns ISO 8601 (or null when carrier hasn't published
    // an ETA yet). We pass it through unchanged; the caller runs
    // resolveETAUpdate to decide whether to write.
    const etaAt = info.time_metrics?.estimated_delivery_date ?? null;

    results.push({
      tracking_number: item.number,
      status,
      carrier,
      latest_checkpoint: latestCheckpoint,
      shipped_at: null, // v2.2 doesn't expose a 'shipped_at' event directly
      delivered_at: deliveredAt,
      eta_at: etaAt,
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
      eta_at: null,
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
