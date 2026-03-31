/**
 * Helper functions for parsing common data formats and building records.
 * Agents and hooks can use these to auto-capture data from conversations.
 */

import {
  MeasurementData,
  DeliveryData,
  CostSummaryData,
  AggregatedTokenUsage,
  TokenUsageRecord,
} from './types';

/**
 * Parse weight entry from natural language.
 * Extracts weight value and unit from text like "I weigh 82.5kg" or "my weight is 180 lbs".
 *
 * @param text - Natural language text containing weight information
 * @returns MeasurementData object or null if no weight found
 */
export function parseWeightEntry(text: string): MeasurementData | null {
  if (!text) return null;

  // Match patterns like "82.5 kg", "82.5kg", "180 lbs", "180lbs", "180 pounds"
  const weightPattern = /(\d+(?:\.\d+)?)\s*(kg|kilograms|lbs?|pounds?)/gi;
  const match = weightPattern.exec(text);

  if (!match) return null;

  const value = parseFloat(match[1]);
  const unitRaw = match[2].toLowerCase();

  let unit = 'kg';
  if (unitRaw.includes('lb') || unitRaw.includes('pound')) {
    unit = 'lbs';
  } else if (unitRaw.includes('kg') || unitRaw.includes('kilogram')) {
    unit = 'kg';
  }

  if (isNaN(value)) return null;

  return {
    value,
    unit,
    notes: text.length > 100 ? text.substring(0, 100) : text,
  };
}

/**
 * Parse delivery status from natural language.
 * Extracts carrier, tracking number, and status from text.
 *
 * Examples:
 * - "Package from Amazon with tracking Z1234567890 arrived"
 * - "FedEx delivery #1234567890 out for delivery"
 * - "UPS tracking 1Z123A4567123456789 delivered yesterday"
 *
 * @param text - Natural language text containing delivery information
 * @returns DeliveryData object or null if no delivery info found
 */
export function parseDeliveryStatus(text: string): DeliveryData | null {
  if (!text) return null;

  // Try to detect carrier
  let carrier = 'unknown';
  const carrierPattern = /(amazon|fedex|ups|usps|dhl|dpd)/gi;
  const carrierMatch = carrierPattern.exec(text);
  if (carrierMatch) {
    carrier = carrierMatch[1].toLowerCase();
  }

  // Try to extract tracking number (common formats)
  let tracking_number = '';
  const trackingPatterns = [
    /tracking\s*#?\s*([A-Z0-9]{10,})/gi,
    /track\s*([A-Z0-9]{10,})/gi,
    /([1Z][A-Z0-9]{16})/g, // UPS format
    /\b([A-Z0-9]{20,})\b/g, // Generic long alphanumeric
  ];

  for (const pattern of trackingPatterns) {
    const match = pattern.exec(text);
    if (match) {
      tracking_number = match[1];
      break;
    }
  }

  if (!tracking_number) {
    return null; // No tracking number found
  }

  // Try to detect status
  let status = 'unknown';
  const statusMap: Record<string, string> = {
    delivered: 'delivered',
    arrived: 'delivered',
    received: 'delivered',
    'out for delivery': 'out_for_delivery',
    'in transit': 'in_transit',
    'in delivery': 'in_delivery',
    pending: 'pending',
    processing: 'processing',
  };

  for (const [key, value] of Object.entries(statusMap)) {
    if (text.toLowerCase().includes(key)) {
      status = value;
      break;
    }
  }

  return {
    carrier,
    tracking_number,
    status,
  };
}

/**
 * Build a cost_summary record from token usage data.
 * Aggregates usage by model and calculates estimated cost.
 *
 * Uses simplified pricing:
 * - Opus 4.6: $15/M input tokens, $75/M output tokens
 * - Other models: estimated based on token counts
 *
 * @param usageData - Array of TokenUsageRecord objects
 * @returns CostSummaryData object
 */
export function buildCostSummary(usageData: TokenUsageRecord[]): CostSummaryData {
  let totalInputTokens = 0;
  let totalOutputTokens = 0;
  let totalEstimatedCost = 0;

  for (const usage of usageData) {
    totalInputTokens += usage.input_tokens || 0;
    totalOutputTokens += usage.output_tokens || 0;
    totalEstimatedCost += usage.estimated_cost_usd || 0;
  }

  return {
    total_cost_usd: parseFloat(totalEstimatedCost.toFixed(6)),
    input_tokens: totalInputTokens,
    output_tokens: totalOutputTokens,
    model: usageData.length > 0 ? usageData[0].model : 'unknown',
  };
}

/**
 * Aggregate token usage by model.
 *
 * @param usageData - Array of TokenUsageRecord objects
 * @returns AggregatedTokenUsage with breakdown by model
 */
export function aggregateTokenUsage(usageData: TokenUsageRecord[]): AggregatedTokenUsage {
  const byModel: Record<string, {
    input_tokens: number;
    output_tokens: number;
    estimated_cost_usd: number;
  }> = {};

  let totalInputTokens = 0;
  let totalOutputTokens = 0;
  let totalCostUsd = 0;

  for (const usage of usageData) {
    totalInputTokens += usage.input_tokens || 0;
    totalOutputTokens += usage.output_tokens || 0;
    totalCostUsd += usage.estimated_cost_usd || 0;

    if (!byModel[usage.model]) {
      byModel[usage.model] = {
        input_tokens: 0,
        output_tokens: 0,
        estimated_cost_usd: 0,
      };
    }

    byModel[usage.model].input_tokens += usage.input_tokens || 0;
    byModel[usage.model].output_tokens += usage.output_tokens || 0;
    byModel[usage.model].estimated_cost_usd += usage.estimated_cost_usd || 0;
  }

  return {
    total_input_tokens: totalInputTokens,
    total_output_tokens: totalOutputTokens,
    total_cost_usd: parseFloat(totalCostUsd.toFixed(6)),
    by_model: byModel,
  };
}
