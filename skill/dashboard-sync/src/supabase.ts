/**
 * Supabase client initialization and configuration.
 * Uses service role key for unrestricted write access to the database.
 */

import { createClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl) {
  throw new Error('SUPABASE_URL environment variable is required');
}

if (!supabaseServiceRoleKey) {
  throw new Error('SUPABASE_SERVICE_ROLE_KEY environment variable is required');
}

/**
 * Supabase client with service role key.
 * This bypasses RLS policies for administrative operations.
 * Used only for internal server-side operations.
 */
export const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);

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
