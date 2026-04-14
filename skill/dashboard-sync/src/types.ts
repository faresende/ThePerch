/**
 * Type definitions for the dashboard-sync skill.
 * Covers all record types, tool parameters, and response shapes.
 */

export type RecordType = 'measurement' | 'delivery' | 'event' | 'status' | 'reminder' | 'text_note' | 'checklist' | 'cost_summary' | 'bookmark' | 'order' | 'shipment' | 'review_item';
export type RecordCategory = 'health' | 'deliveries' | 'calendar' | 'admin' | 'legal' | 'bookmarks' | 'commerce';
export type DisplayHint = 'chart' | 'single_value' | 'status_list' | 'timeline' | 'checklist' | 'cost_breakdown' | 'bookmark_card' | 'bookmark_grid' | 'order_card' | 'shipment_timeline' | 'review_item_card';

/**
 * Type-specific data payloads
 */
export interface MeasurementData {
  value: number;
  unit: string;
  notes?: string;
}

export interface DeliveryData {
  carrier: string;
  tracking_number: string;
  status: string;
  delivery_date?: string;
}

// Orders Autopilot types
export type OrderStatus = 'ordered' | 'processing' | 'shipped_partial' | 'shipped' | 'delivered' | 'cancelled' | 'issue';
export type ShipmentStatus = 'unknown' | 'label_created' | 'in_transit' | 'out_for_delivery' | 'delivered' | 'exception';
export type ReviewItemType = 'duplicate_order' | 'orphan_shipment' | 'order_no_shipment' | 'shipment_no_order' | 'low_confidence_match' | 'ambiguous_order_match' | 'missing_order_for_tracking' | 'missing_tracking_for_order' | 'other';

export interface OrderData {
  record_type?: 'order';
  order_id?: string;
  merchant_name: string;
  normalized_merchant?: string;
  order_number: string | null;
  order_date: string | null;
  total_amount?: number | null;
  currency: string;
  status: OrderStatus;
  confidence_score: number;
  source_email_ids?: string[];
  created_at?: string;
}

export interface ShipmentData {
  record_type?: 'shipment';
  shipment_id?: string;
  order_id?: string;
  tracking_number: string;
  carrier: string | null;
  status: ShipmentStatus;
  latest_checkpoint?: string | null;
  shipped_at?: string | null;
  delivered_at?: string | null;
  confidence_score: number;
  source_email_ids?: string[];
  /** Transient fields set during extraction / matching, not stored in DB */
  merchant_name?: string;
  normalized_merchant?: string;
  order_number?: string;
  provider?: string;
}

export interface ReviewItemData {
  record_type?: 'review_item';
  review_item_id?: string;
  type: ReviewItemType;
  related_order_id?: string | null;
  related_shipment_id?: string | null;
  reason: string;
  suggested_action?: string | null;
  confidence_score: number;
  created_at?: string;
}

export interface EventData {
  start_time: string;
  end_time?: string;
  location?: string;
  attendees?: string[];
}

export interface ReminderData {
  due_date: string;
  description: string;
  priority?: 'low' | 'medium' | 'high';
}

export interface ChecklistData {
  items: Array<{
    text: string;
    completed: boolean;
  }>;
  progress?: number;
}

export interface CostSummaryData {
  total_cost_usd: number;
  input_tokens: number;
  output_tokens: number;
  model: string;
}

export type BookmarkStatus = 'pending' | 'processing' | 'processed' | 'failed';

/**
 * Bookmark data — submitted from iOS Share Extension, Safari Extension, or Telegram.
 * Initially created with status 'pending', then enriched by the Archie agent.
 */
export interface BookmarkData {
  url: string;
  original_title?: string;
  enriched_title?: string;
  summary?: string;
  tags: string[];
  status: BookmarkStatus;
  domain?: string;
  image_url?: string;
  reading_time_minutes?: number;
  submitted_from?: 'ios_share' | 'safari_extension' | 'telegram' | 'webchat';
  processed_at?: string;
}

export type RecordData =
  | MeasurementData
  | DeliveryData
  | EventData
  | ReminderData
  | ChecklistData
  | CostSummaryData
  | BookmarkData
  | OrderData
  | ShipmentData
  | ReviewItemData
  | Record<string, unknown>;

/**
 * Dashboard record as stored in the database
 */
export interface DashboardRecord {
  id: string;
  agent_id: string;
  user_id: string;
  type: RecordType;
  category: RecordCategory;
  title: string;
  data: RecordData;
  display_hint?: DisplayHint;
  annotations?: Record<string, unknown>;
  pinned: boolean;
  created_at: string;
  updated_at: string;
  expires_at?: string;
}

/**
 * Agent record as stored in the database
 */
export interface AgentRecord {
  id: string;
  display_name: string;
  emoji?: string;
  model?: string;
  is_active: boolean;
  last_heartbeat: string;
  owner_id: string;
}

/**
 * Token usage record as stored in the database
 */
export interface TokenUsageRecord {
  id: string;
  agent_id: string;
  date: string;
  input_tokens: number;
  output_tokens: number;
  model: string;
  estimated_cost_usd: number;
}

/**
 * Tool: dashboard_push
 */
export interface DashboardPushInput {
  agent_id: string;
  user_id: string;
  type: RecordType;
  category: RecordCategory;
  title: string;
  data: RecordData;
  display_hint?: DisplayHint;
  annotations?: Record<string, unknown>;
  pinned?: boolean;
  expires_at?: string;
}

export interface DashboardPushOutput {
  success: boolean;
  id?: string;
  created_at?: string;
  error?: string;
}

/**
 * Tool: dashboard_query
 */
export interface DashboardQueryInput {
  user_id: string;
  type?: RecordType;
  category?: RecordCategory;
  agent_id?: string;
  limit?: number;
  since?: string;
}

export interface DashboardQueryOutput {
  records: DashboardRecord[];
  count: number;
  error?: string;
}

/**
 * Tool: dashboard_heartbeat
 */
export interface DashboardHeartbeatInput {
  agent_id: string;
  user_id: string;
  display_name?: string;
  emoji?: string;
  model?: string;
  is_active?: boolean;
  input_tokens?: number;
  output_tokens?: number;
  estimated_cost_usd?: number;
}

export interface DashboardHeartbeatOutput {
  success: boolean;
  agent_updated?: boolean;
  usage_recorded?: boolean;
  gateway_updated?: boolean;
  last_heartbeat?: string;
  error?: string;
}

/**
 * Aggregated token usage for cost summary
 */
export interface AggregatedTokenUsage {
  total_input_tokens: number;
  total_output_tokens: number;
  total_cost_usd: number;
  by_model: Record<string, {
    input_tokens: number;
    output_tokens: number;
    estimated_cost_usd: number;
  }>;
}
