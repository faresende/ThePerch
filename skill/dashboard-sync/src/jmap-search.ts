/**
 * jmap-search.ts
 *
 * Minimal Fastmail JMAP client for the orders-autopilot's tracking
 * cross-reference. We use it to do one thing reliably: given a
 * tracking number, find the original order-confirmation email that
 * mentioned it, so we can pull the actual merchant from THAT email's
 * sender — not from whatever the carrier email said.
 *
 * Why: caught in the wild, Correos / DPD / FedEx shipping notifications
 * sometimes don't mention the merchant cleanly in the body, OR they
 * mention multiple merchants (e.g. "your order from various sellers").
 * The order-confirmation email that originated the tracking number,
 * on the other hand, almost always has the merchant in the From: name
 * or domain. Searching the inbox for the tracking number yields one
 * clear match in 95%+ of cases.
 *
 * Auth: reads `FASTMAIL_API_TOKEN` from env first, falls back to macOS
 * Keychain (`security find-generic-password -a fastmail-jmap …`),
 * which is where the Python listener stores it. Either source works.
 */

import { execSync } from 'node:child_process';

const SESSION_URL = 'https://api.fastmail.com/jmap/session';

interface JMAPSession {
  apiUrl: string;
  accountId: string;
  token: string;
}

let cachedSession: JMAPSession | null = null;

function getToken(): string {
  const fromEnv = process.env.FASTMAIL_API_TOKEN;
  if (fromEnv && fromEnv.trim()) return fromEnv.trim();
  try {
    return execSync(
      "security find-generic-password -a 'fastmail-jmap' -s 'fastmail-jmap-token' -w",
      { encoding: 'utf-8', stdio: ['ignore', 'pipe', 'ignore'] },
    ).trim();
  } catch {
    return '';
  }
}

async function getSession(): Promise<JMAPSession | null> {
  if (cachedSession) return cachedSession;
  const token = getToken();
  if (!token) return null;

  try {
    const res = await fetch(SESSION_URL, {
      headers: { 'Authorization': `Bearer ${token}` },
    });
    if (!res.ok) return null;
    const data = await res.json() as { apiUrl: string; accounts: Record<string, unknown> };
    const accountId = Object.keys(data.accounts)[0];
    if (!accountId) return null;
    cachedSession = { apiUrl: data.apiUrl, accountId, token };
    return cachedSession;
  } catch {
    return null;
  }
}

export interface EmailMeta {
  id: string;
  subject: string;
  fromName: string;
  fromEmail: string;
  receivedAt: string;
}

/**
 * Search across the user's mailbox for emails matching a free-text
 * query. Returns lightweight metadata only (subject + sender + date),
 * sorted most-recent-first, capped at `limit`.
 *
 * `query` is matched against subject + body via JMAP's `text` filter.
 * Returns [] when the JMAP token isn't available or the call fails —
 * the cross-reference step is best-effort and must never break the
 * pipeline.
 */
export async function searchEmailsByText(
  query: string,
  limit: number = 8,
): Promise<EmailMeta[]> {
  const session = await getSession();
  if (!session) return [];

  try {
    const res = await fetch(session.apiUrl, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${session.token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        using: ['urn:ietf:params:jmap:core', 'urn:ietf:params:jmap:mail'],
        methodCalls: [
          ['Email/query', {
            accountId: session.accountId,
            filter: { text: query },
            sort: [{ property: 'receivedAt', isAscending: false }],
            limit,
          }, '0'],
          ['Email/get', {
            accountId: session.accountId,
            '#ids': { resultOf: '0', name: 'Email/query', path: '/ids' },
            properties: ['id', 'subject', 'from', 'receivedAt'],
          }, '1'],
        ],
      }),
    });
    if (!res.ok) return [];
    const data = await res.json() as {
      methodResponses?: Array<[string, { list?: Array<{
        id: string;
        subject?: string;
        from?: Array<{ name?: string; email?: string }>;
        receivedAt?: string;
      }> }, string]>;
    };
    const list = data.methodResponses?.[1]?.[1]?.list ?? [];
    return list.map(em => ({
      id: em.id,
      subject: em.subject ?? '',
      fromName: em.from?.[0]?.name ?? '',
      fromEmail: em.from?.[0]?.email ?? '',
      receivedAt: em.receivedAt ?? '',
    }));
  } catch (err) {
    console.warn(`[jmap-search] search failed: ${err instanceof Error ? err.message : err}`);
    return [];
  }
}
