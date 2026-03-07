/**
 * Bookmark Watcher for The Perch
 *
 * Polls Supabase for pending bookmarks submitted via iOS Share Extension
 * or Safari Extension, then triggers OpenClaw's Archie agent to enrich them.
 *
 * Designed to run as an OpenClaw cron job every 2 minutes.
 */

import { SupabaseClient } from '@supabase/supabase-js';
import { supabase } from './supabase';

/** Suggested cron expression: every 2 minutes */
export const BOOKMARK_WATCHER_CRON = '*/2 * * * *';

/** Max bookmarks to process per run (avoid overwhelming the agent) */
const MAX_PER_RUN = 5;

/** Minutes before a 'processing' bookmark is considered stuck */
const TIMEOUT_MINUTES = 10;

/** OpenClaw webhook endpoint for triggering agent runs */
const OPENCLAW_WEBHOOK = 'http://127.0.0.1:18789/hooks/agent';

/** Data returned by the agent after enrichment */
export interface EnrichedBookmarkData {
  title?: string;
  summary?: string;
  tags?: string[];
  reading_time?: number;
  image_url?: string;
}

// ────────────────────────────────────────────────────────────────────────────
// Main watcher
// ────────────────────────────────────────────────────────────────────────────

/**
 * Main entry point. Call this on a cron schedule.
 * 1. Marks stuck bookmarks as failed
 * 2. Picks up pending bookmarks
 * 3. Sends each to OpenClaw for agent processing
 */
export async function watchPendingBookmarks(agentId: string = 'main'): Promise<void> {
  console.log('[BookmarkWatcher] Starting watch cycle');

  // 1. Handle stuck bookmarks (processing > 10 min)
  await handleStuckBookmarks();

  // 2. Fetch pending bookmarks
  const { data: pending, error } = await supabase
    .from('bookmarks')
    .select('id, url, original_title, tags, user_id')
    .eq('status', 'pending')
    .order('created_at', { ascending: true })
    .limit(MAX_PER_RUN);

  if (error) {
    console.error('[BookmarkWatcher] Error fetching pending bookmarks:', error.message);
    return;
  }

  if (!pending || pending.length === 0) {
    console.log('[BookmarkWatcher] No pending bookmarks');
    return;
  }

  console.log(`[BookmarkWatcher] Found ${pending.length} pending bookmarks`);

  // 3. Process each one
  for (const bookmark of pending) {
    try {
      await processOne(bookmark, agentId);
    } catch (err) {
      console.error(`[BookmarkWatcher] Failed to process ${bookmark.id}:`, err);
      await failBookmark(bookmark.id, String(err));
    }
  }

  console.log('[BookmarkWatcher] Watch cycle complete');
}

// ────────────────────────────────────────────────────────────────────────────
// Process a single bookmark
// ────────────────────────────────────────────────────────────────────────────

async function processOne(
  bookmark: { id: string; url: string; original_title: string | null; tags: string[] | null; user_id: string },
  agentId: string
): Promise<void> {
  // Mark as processing
  const { error: updateErr } = await supabase
    .from('bookmarks')
    .update({ status: 'processing', updated_at: new Date().toISOString() })
    .eq('id', bookmark.id);

  if (updateErr) {
    throw new Error(`Failed to mark as processing: ${updateErr.message}`);
  }

  console.log(`[BookmarkWatcher] Processing ${bookmark.id} — ${bookmark.url}`);

  // Build the agent message
  const message = [
    `Process this bookmark: ${bookmark.url}`,
    bookmark.original_title ? `Original title: "${bookmark.original_title}"` : '',
    bookmark.tags?.length ? `User tags: ${bookmark.tags.join(', ')}` : '',
    '',
    'Extract or improve the title, write a 2-3 sentence summary, suggest relevant tags (as a comma-separated list), and estimate reading time in minutes.',
    'Format your response as JSON with keys: title, summary, tags (array of strings), reading_time (number).',
    '',
    `When done, call dashboard_push with type "bookmark", category "bookmarks", and include bookmarkId "${bookmark.id}" in annotations so I can link it back.`,
  ].filter(Boolean).join('\n');

  // Fire webhook to OpenClaw
  const resp = await fetch(OPENCLAW_WEBHOOK, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      agentId,
      message,
      metadata: {
        bookmarkId: bookmark.id,
        source: 'bookmark-watcher',
      },
    }),
  });

  if (!resp.ok) {
    throw new Error(`Webhook returned ${resp.status}: ${resp.statusText}`);
  }

  console.log(`[BookmarkWatcher] Queued ${bookmark.id} for agent ${agentId}`);
}

// ────────────────────────────────────────────────────────────────────────────
// Handle stuck bookmarks
// ────────────────────────────────────────────────────────────────────────────

async function handleStuckBookmarks(): Promise<void> {
  const cutoff = new Date(Date.now() - TIMEOUT_MINUTES * 60_000).toISOString();

  const { data: stuck, error } = await supabase
    .from('bookmarks')
    .select('id')
    .eq('status', 'processing')
    .lt('updated_at', cutoff);

  if (error) {
    console.error('[BookmarkWatcher] Error checking stuck bookmarks:', error.message);
    return;
  }

  if (stuck && stuck.length > 0) {
    console.log(`[BookmarkWatcher] Found ${stuck.length} stuck bookmarks, marking as failed`);
    for (const b of stuck) {
      await failBookmark(b.id, 'Processing timeout: exceeded 10 minutes');
    }
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Complete / Fail helpers (exported for use by agent callback)
// ────────────────────────────────────────────────────────────────────────────

/**
 * Called after the agent finishes enriching a bookmark.
 * Updates the bookmark with enriched data and sets status to 'processed'.
 */
export async function completeBookmark(
  bookmarkId: string,
  enriched: EnrichedBookmarkData
): Promise<void> {
  const update: Record<string, unknown> = {
    status: 'processed',
    processed_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };

  if (enriched.title) update.enriched_title = enriched.title;
  if (enriched.summary) update.summary = enriched.summary;
  if (enriched.tags) update.tags = enriched.tags;
  if (enriched.reading_time) update.reading_time_minutes = enriched.reading_time;
  if (enriched.image_url) update.image_url = enriched.image_url;

  const { error } = await supabase
    .from('bookmarks')
    .update(update)
    .eq('id', bookmarkId);

  if (error) {
    console.error(`[BookmarkWatcher] Failed to complete ${bookmarkId}:`, error.message);
    throw error;
  }

  console.log(`[BookmarkWatcher] Completed ${bookmarkId}`);
}

/**
 * Marks a bookmark as failed with an error message.
 */
export async function failBookmark(bookmarkId: string, errorMsg: string): Promise<void> {
  const { error } = await supabase
    .from('bookmarks')
    .update({
      status: 'failed',
      updated_at: new Date().toISOString(),
    })
    .eq('id', bookmarkId);

  if (error) {
    console.error(`[BookmarkWatcher] Failed to mark ${bookmarkId} as failed:`, error.message);
    return;
  }

  console.log(`[BookmarkWatcher] Marked ${bookmarkId} as failed: ${errorMsg}`);
}
