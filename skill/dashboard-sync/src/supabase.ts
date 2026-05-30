/**
 * Supabase client initialization and configuration.
 * Uses service role key for unrestricted write access to the database.
 */

import { createClient, SupabaseClient } from '@supabase/supabase-js';

/**
 * Build the real client, asserting required env vars are present.
 * Called lazily on first property access (see Proxy below) so that merely
 * importing this module — e.g. to unit-test a pure helper that happens to live
 * in a module which transitively imports supabase — does NOT throw when the
 * environment isn't configured. Any actual DB operation still requires env and
 * surfaces the same error.
 */
function buildClient(): SupabaseClient {
  const supabaseUrl = process.env.SUPABASE_URL;
  const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!supabaseUrl) {
    throw new Error('SUPABASE_URL environment variable is required');
  }

  if (!supabaseServiceRoleKey) {
    throw new Error('SUPABASE_SERVICE_ROLE_KEY environment variable is required');
  }

  return createClient(supabaseUrl, supabaseServiceRoleKey);
}

let _client: SupabaseClient | null = null;
function client(): SupabaseClient {
  if (!_client) _client = buildClient();
  return _client;
}

/**
 * Supabase client with service role key.
 * This bypasses RLS policies for administrative operations.
 * Used only for internal server-side operations.
 *
 * Lazily initialized: the underlying client (and its env-var assertions) is
 * created on first property access, not at import time.
 */
export const supabase: SupabaseClient = new Proxy({} as SupabaseClient, {
  get(_target, prop, receiver) {
    const real = client() as unknown as Record<string | symbol, unknown>;
    const value = Reflect.get(real, prop, receiver);
    return typeof value === 'function' ? value.bind(real) : value;
  },
});

/**
 * Health check: verify connection to Supabase
 * @returns true if connection is valid, false otherwise
 */
export async function verifyConnection(): Promise<boolean> {
  try {
    const { error } = await supabase.from('agents').select('id').limit(1);
    return !error;
  } catch (error) {
    console.error('Supabase connection verification failed:', error);
    return false;
  }
}

export default supabase;
