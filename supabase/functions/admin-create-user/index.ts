// admin-create-user
//
// Creates a new Supabase Auth user on behalf of an allowlisted admin caller.
// Designed to be invoked server-to-server by Claudinho (home Mac mini agent),
// not by the iOS app directly.
//
// Request:
//   POST /functions/v1/admin-create-user
//   Authorization: Bearer <JWT of an admin user who is on ADMIN_USER_UUIDS>
//   Content-Type: application/json
//   Body: {
//     "email": "person@example.com",              // required
//     "password": "at-least-twelve-chars",        // optional (random if omitted)
//     "user_metadata": { ... },                   // optional JSON object
//     "app_metadata": { ... },                    // optional JSON object
//     "email_confirm": true                       // optional, defaults true
//   }
//
// Success response (201):
//   { "user": { "id": "uuid", "email": "person@example.com", "created_at": "..." } }
//
// Failure responses:
//   400  invalid body
//   401  missing or invalid JWT
//   403  caller not on ADMIN_USER_UUIDS allowlist
//   409  email already registered
//   500  internal error or missing env vars
//   503  allowlist unconfigured (fails closed)

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json',
};

class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

type CreateUserRequest = {
  email: string;
  password?: string;
  user_metadata?: Record<string, unknown>;
  app_metadata?: Record<string, unknown>;
  email_confirm?: boolean;
};

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  try {
    const callerId = await requireAdminCaller(req);
    const body = await parseRequestBody(req);
    const admin = createServiceClient();

    const { data, error } = await admin.auth.admin.createUser({
      email: body.email,
      password: body.password,
      user_metadata: body.user_metadata,
      app_metadata: body.app_metadata,
      email_confirm: body.email_confirm ?? true,
    });

    if (error) {
      const msg = error.message ?? 'Unknown createUser error';
      if (
        error.status === 422 ||
        msg.toLowerCase().includes('already registered') ||
        msg.toLowerCase().includes('already been registered')
      ) {
        throw new HttpError(409, `User already exists: ${msg}`);
      }
      throw new HttpError(error.status ?? 500, msg);
    }
    if (!data?.user) {
      throw new HttpError(500, 'User creation returned no user');
    }

    console.log(
      `admin-create-user: caller=${callerId} created=${data.user.id} email=${data.user.email}`,
    );

    return jsonResponse(
      {
        user: {
          id: data.user.id,
          email: data.user.email,
          created_at: data.user.created_at,
        },
      },
      201,
    );
  } catch (error) {
    return handleError(error);
  }
});

async function requireAdminCaller(req: Request): Promise<string> {
  const authHeader = req.headers.get('authorization') ?? '';
  const match = authHeader.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    throw new HttpError(401, 'Missing or malformed Authorization header');
  }
  const jwt = match[1].trim();
  if (!jwt) {
    throw new HttpError(401, 'Empty bearer token');
  }

  const supabaseUrl = requireEnv('SUPABASE_URL');
  const anonKey = requireEnv('SUPABASE_ANON_KEY');
  const supabase = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data, error } = await supabase.auth.getUser(jwt);
  if (error || !data?.user) {
    throw new HttpError(401, 'Invalid or expired JWT');
  }

  const allowlistRaw = Deno.env.get('ADMIN_USER_UUIDS') ?? '';
  const allowlist = allowlistRaw
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);

  if (allowlist.length === 0) {
    console.error(
      'admin-create-user: ADMIN_USER_UUIDS is empty; denying all callers by default',
    );
    throw new HttpError(503, 'Admin allowlist is not configured');
  }
  if (!allowlist.includes(data.user.id)) {
    console.warn(
      `admin-create-user: denied non-admin caller user=${data.user.id} email=${data.user.email ?? '?'}`,
    );
    throw new HttpError(403, 'Forbidden: caller is not on the admin allowlist');
  }

  return data.user.id;
}

async function parseRequestBody(req: Request): Promise<CreateUserRequest> {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    throw new HttpError(400, 'Invalid JSON body');
  }
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw new HttpError(400, 'Body must be a JSON object');
  }
  const b = body as Record<string, unknown>;

  if (typeof b.email !== 'string' || !b.email.includes('@')) {
    throw new HttpError(400, 'Missing or invalid "email"');
  }
  if (
    b.password !== undefined &&
    (typeof b.password !== 'string' || b.password.length < 12)
  ) {
    throw new HttpError(
      400,
      '"password" must be a string of at least 12 characters when provided',
    );
  }
  if (
    b.user_metadata !== undefined &&
    (typeof b.user_metadata !== 'object' ||
      b.user_metadata === null ||
      Array.isArray(b.user_metadata))
  ) {
    throw new HttpError(400, '"user_metadata" must be a JSON object');
  }
  if (
    b.app_metadata !== undefined &&
    (typeof b.app_metadata !== 'object' ||
      b.app_metadata === null ||
      Array.isArray(b.app_metadata))
  ) {
    throw new HttpError(400, '"app_metadata" must be a JSON object');
  }
  if (b.email_confirm !== undefined && typeof b.email_confirm !== 'boolean') {
    throw new HttpError(400, '"email_confirm" must be a boolean');
  }

  return {
    email: b.email,
    password: b.password as string | undefined,
    user_metadata: b.user_metadata as Record<string, unknown> | undefined,
    app_metadata: b.app_metadata as Record<string, unknown> | undefined,
    email_confirm: b.email_confirm as boolean | undefined,
  };
}

function createServiceClient() {
  const supabaseUrl = requireEnv('SUPABASE_URL');
  const serviceRoleKey = requireEnv('SUPABASE_SERVICE_ROLE_KEY');
  return createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new HttpError(500, `${name} is not configured on this function`);
  }
  return value;
}

function handleError(error: unknown): Response {
  if (error instanceof HttpError) {
    return jsonResponse({ error: error.message }, error.status);
  }
  const message = error instanceof Error ? error.message : 'Internal server error';
  return jsonResponse({ error: message }, 500);
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: CORS_HEADERS,
  });
}
