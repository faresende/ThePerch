#!/usr/bin/env python3
"""
fetch_fixtures.py — pull email fixtures from Fastmail JMAP for the
classifier regression suite.

Usage (one-shot, requires `~/.openclaw/secrets/perch.env` sourced):
    python3 test/fixtures/fetch_fixtures.py

Each FIXTURE entry below produces one JSON file under
`test/fixtures/{orders,rejections}/`. Bodies are truncated to 30,000
chars (enough to match every signal/regex in the classifier).

To add a new fixture: append a tuple to FIXTURES with
    (jmap_email_id, "orders" | "rejections", expected_dict)
where `expected_dict` is the shape the test runner asserts on:
    {"type": "purchase_confirmation"|"shipping_notification"|"other",
     "merchant": "Hardgraft" or None,
     "order_number": "HGMC20117325" or None}
"""

import json, os, sys
sys.path.insert(0, os.path.expanduser('~/.openclaw/workspace/sandbox/fastmail-jmap'))
from jmap_client import get_token, get_session, jmap_call

FIXTURES = [
    # ─── orders/ — should classify as purchase_confirmation ───────────
    ('StpOX7d3213w', 'orders', 'hardgraft-hgmc20117325',
     {'type': 'purchase_confirmation', 'merchant': 'Hardgraft',
      'order_number': 'HGMC20117325'}),
    ('StpOIQFUIF97', 'orders', 'bodyfit-bf1429199',
     {'type': 'purchase_confirmation', 'merchant': 'Body&Fit',
      'order_number': 'BF1429199'}),
    ('StpOI6hH-QyJ', 'orders', 'jmm-104383',
     {'type': 'purchase_confirmation', 'merchant': 'Jacques Marie Mage',
      'order_number': '104383'}),
    ('StpOHwRY6c6F', 'orders', 'vulkit-108984',
     {'type': 'purchase_confirmation', 'merchant': 'Vulkit',
      'order_number': '108984'}),
    ('StpOHcI8TGDJ', 'orders', 'matador-1723',
     {'type': 'purchase_confirmation', 'merchant': 'Matador',
      'order_number': '1723'}),

    # ─── rejections/ — should NOT classify as purchase_confirmation.
    # 'other' = clean drop (no commerce signal at all, e.g. trip
    # reminder).
    # 'shipping_notification' = legitimately a shipping email but from
    # a carrier (Correos, DHL, …) — should NEVER be a fresh purchase
    # because the user hasn't bought anything from the carrier.
    ('StpNL9mnCSNc', 'rejections', 'amex-trip-reminder',
     {'type': 'other'}),
    ('StpNE-NH6_1V', 'rejections', 'elcorteingles-receipt',
     {'type': 'other'}),
    ('StpN9xkaL6Gg', 'rejections', 'correos-express-shipping',
     {'type': 'shipping_notification'}),
]

ROOT = os.path.dirname(os.path.abspath(__file__))


def main() -> None:
    session = get_session(get_token())
    ids = [f[0] for f in FIXTURES]
    print(f'Fetching {len(ids)} email fixtures from JMAP…')

    responses = jmap_call(session, [
        ['Email/get', {
            'accountId': session['accountId'],
            'ids': ids,
            'properties': ['id', 'subject', 'from', 'receivedAt',
                           'textBody', 'htmlBody', 'bodyValues'],
            'fetchTextBodyValues': True,
            'fetchHTMLBodyValues': True,
            'maxBodyValueBytes': 100_000,
        }, '0'],
    ])
    by_id = {em['id']: em for em in responses[0][1]['list']}

    for eid, bucket, slug, expected in FIXTURES:
        em = by_id.get(eid)
        if not em:
            print(f'  ! {slug}: email {eid} not found, skipping')
            continue
        sender_obj = (em.get('from') or [{}])[0]
        sender_email = sender_obj.get('email', '')
        sender_name = sender_obj.get('name', '') or ''
        body_parts = em.get('textBody') or em.get('htmlBody') or []
        body = ''
        for p in body_parts:
            bv = (em.get('bodyValues') or {}).get(p['partId'], {})
            if bv.get('value'):
                body += bv['value']
        body = body[:30_000]

        fixture = {
            'label': slug,
            'source_email_id': eid,
            'input': {
                'subject': em.get('subject', ''),
                'sender': f'{sender_name} <{sender_email}>'
                          if sender_name else sender_email,
                'senderName': sender_name,
                'senderEmail': sender_email,
                'date': em.get('receivedAt', ''),
                'body': body,
            },
            'expected': expected,
        }

        out_dir = os.path.join(ROOT, bucket)
        os.makedirs(out_dir, exist_ok=True)
        out_path = os.path.join(out_dir, f'{slug}.json')
        with open(out_path, 'w') as f:
            json.dump(fixture, f, indent=2, ensure_ascii=False)
        print(f'  ✓ {bucket}/{slug}.json ({len(body)} body chars)')

    print('\nDone. Run `npm test` to verify all fixtures pass.')


if __name__ == '__main__':
    main()
