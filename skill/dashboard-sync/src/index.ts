/**
 * Dashboard Sync Skill
 * Provides tools for persisting structured data to Supabase for the iOS dashboard.
 */

import { supabase } from './supabase';
import {
  DashboardPushInput,
  DashboardPushOutput,
  DashboardQueryInput,
  DashboardQueryOutput,
  DashboardHeartbeatInput,
  DashboardHeartbeatOutput,
  RecordType,
  RecordCategory,
  DisplayHint,
} from './types';

/**
 * Validates record input parameters
 * @throws Error if validation fails
 */
function validatePushInput(input: DashboardPushInput): void {
  if (!input.agent_id || typeof input.agent_id !== 'string') {
    throw new Error('agent_id must be a non-empty string');
  }

  if (!input.user_id || typeof input.user_id !== 'string') {
    throw new Error('user_id must be a non-empty string');
  }

  const validTypes: RecordType[] = [
    'measurement',
    'delivery',
    'event',
    'status',
    'reminder',
    'text_note',
    'checklist',
    'cost_summary',
    'bookmark',
  ];
  if (!validTypes.includes(input.type)) {
    throw new Error(`type must be one of: ${validTypes.join(', ')}`);
  }

  const validCategories: RecordCategory[] = [
    'health',
    'deliveries',
    'calendar',
    'admin',
    'legal',
    'bookmarks',
  ];
  if (!validCategories.includes(input.category)) {
    throw new Error(`category must be one of: ${validCategories.join(', ')}`);
  }

  if (!input.title || typeof input.title !== 'string') {
    throw new Error('title must be a non-empty string');
  }

  if (!input.data || typeof input.data !== 'object') {
    throw new Error('data must be an object');
  }

  if (input.display_hint) {
    const validHints: DisplayHint[] = [
      'chart',
      'single_value',
      'status_list',
      'timeline',
      'checklist',
      'cost_breakdown',
      'bookmark_card',
      'bookmark_grid',
    ];
    if (!validHints.includes(input.display_hint)) {
      throw new Error(`display_hint must be one of: ${validHints.join(', ')}`);
    }
  }

  if (input.expires_at && typeof input.expires_at !== 'string') {
    throw new Error('expires_at must be an ISO 8601 timestamp string');
  }
}

/**
 * Tool: dashboard_push
 * Saves a structured data record to the dashboard database.
 *
 * @param input - DashboardPushInput parameters
 * @returns DashboardPushOutput with record ID and creation timestamp
 */
export async function dashboard_push(
  input: DashboardPushInput,
): Promise<DashboardPushOutput> {
  try {
    validatePushInput(input);

    const now = new Date().toISOString();

    const record = {
      agent_id: input.agent_id,
      user_id: input.user_id,
      type: input.type,
      category: input.category,
      title: input.title,
      data: input.data,
      display_hint: input.display_hint || null,
      annotations: input.annotations || null,
      pinned: input.pinned ?? false,
      created_at: now,
      updated_at: now,
      expires_at: input.expires_at || null,
    };

    const { data, error } = await supabase
      .from('records')
      .insert([record])
      .select('id, created_at')
      .single();

    if (error) {
      console.error('Failed to insert record:', error);
      return {
        success: false,
        error: error.message || 'Failed to save record to database',
      };
    }

    return {
      success: true,
      id: data.id,
      created_at: data.created_at,
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error('dashboard_push error:', message);
    return {
      success: false,
      error: message,
    };
  }
}

/**
 * Tool: dashboard_query
 * Queries recent records from the database with optional filtering.
 *
 * @param input - DashboardQueryInput parameters
 * @returns DashboardQueryOutput with matching records and count
 */
export async function dashboard_query(
  input: DashboardQueryInput,
): Promise<DashboardQueryOutput> {
  try {
    if (!input.user_id || typeof input.user_id !== 'string') {
      throw new Error('user_id must be a non-empty string');
    }

    const limit = Math.min(input.limit || 50, 500);

    let query = supabase
      .from('records')
      .select('*')
      .eq('user_id', input.user_id);

    if (input.type) {
      query = query.eq('type', input.type);
    }

    if (input.category) {
      query = query.eq('category', input.category);
    }

    if (input.agent_id) {
      query = query.eq('agent_id', input.agent_id);
    }

    if (input.since) {
      query = query.gt('created_at', input.since);
    }

    const { data, error, count } = await query
      .order('created_at', { ascending: false })
      .limit(limit);

    if (error) {
      console.error('Failed to query records:', error);
      return {
        records: [],
        count: 0,
        error: error.message || 'Failed to query records',
      };
    }

    return {
      records: data || [],
      count: count || 0,
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error('dashboard_query error:', message);
    return {
      records: [],
      count: 0,
      error: message,
    };
  }
}

/**
 * Tool: dashboard_heartbeat
 * Updates agent status and logs token usage in a single operation.
 *
 * @param input - DashboardHeartbeatInput parameters
 * @returns DashboardHeartbeatOutput with update status
 */
export async function dashboard_heartbeat(
  input: DashboardHeartbeatInput,
): Promise<DashboardHeartbeatOutput> {
  try {
    if (!input.agent_id || typeof input.agent_id !== 'string') {
      throw new Error('agent_id must be a non-empty string');
    }

    if (!input.user_id || typeof input.user_id !== 'string') {
      throw new Error('user_id must be a non-empty string');
    }

    const now = new Date().toISOString();
    const today = new Date().toISOString().split('T')[0];

    let agent_updated = false;
    let usage_recorded = false;

    // Upsert agent record
    const agentData = {
      id: input.agent_id,
      owner_id: input.user_id,
      last_heartbeat: now,
      ...(input.display_name && { display_name: input.display_name }),
      ...(input.emoji !== undefined && { emoji: input.emoji }),
      ...(input.model !== undefined && { model: input.model }),
      ...(input.is_active !== undefined && { is_active: input.is_active }),
    };

    const { error: agentError } = await supabase
      .from('agents')
      .upsert([agentData], { onConflict: 'id' });

    if (agentError) {
      console.error('Failed to upsert agent:', agentError);
    } else {
      agent_updated = true;
    }

    // Log token usage if provided
    if (
      (input.input_tokens !== undefined || input.output_tokens !== undefined) &&
      input.model
    ) {
      const usageData = {
        agent_id: input.agent_id,
        date: today,
        input_tokens: input.input_tokens || 0,
        output_tokens: input.output_tokens || 0,
        model: input.model,
        estimated_cost_usd: input.estimated_cost_usd || 0,
      };

      const { error: usageError } = await supabase
        .from('token_usage')
        .upsert([usageData], {
          onConflict: 'agent_id,date,model',
        });

      if (usageError) {
        console.error('Failed to record token usage:', usageError);
      } else {
        usage_recorded = true;
      }
    }

    return {
      success: agent_updated || usage_recorded,
      agent_updated,
      usage_recorded,
      last_heartbeat: now,
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error('dashboard_heartbeat error:', message);
    return {
      success: false,
      error: message,
    };
  }
}

/**
 * Tool handlers export for OpenClaw
 */
export const tools = {
  dashboard_push,
  dashboard_query,
  dashboard_heartbeat,
};

export default tools;
