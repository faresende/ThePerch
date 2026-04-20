#!/usr/bin/env python3
"""
orders_autopilot_ingest_fastmail.py
Fetches recent commerce emails from Fastmail (Paper Trail + Inbox),
processes them through the orders autopilot pipeline, and pushes
delivery records to The Perch dashboard_records table.
"""

import json
import os
import re
import sys
import requests
from datetime import datetime, timedelta, timezone

WORKSPACE = os.path.expanduser('~/.openclaw/workspace')
JMAP_DIR = os.path.join(WORKSPACE, 'sandbox/fastmail-jmap')
sys.path.insert(0, JMAP_DIR)

import jmap_client as jc

SUPABASE_BASE = 'https://cgmaotzmeoiueyzlchaz.supabase.co/rest/v1'
SUPABASE_KEY = 'sb_secret_***REDACTED***'
USER_ID = '00000000-0000-0000-0000-000000000000'
HEADERS = {
    'apikey': SUPABASE_KEY,
    'Authorization': f'Bearer {SUPABASE_KEY}',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
}

COMMERCE_SENDERS = [
    'vollebak', 'mr porter', 'dak coffee', 'ace & tate', 'amazon',
    'dhl', 'ups', 'fedex', 'mrport', 'nick and steve',
    'dakcoffe', 'la plantation', 'arnold', 'misterolympia', 'hartem',
]
EXCLUDE_SENDERS = ['glovo', 'uber', 'bolt', 'freenow', 'taxis', 'lyft', 'deliveroo', 'just eat']


def is_commerce_sender(from_email):
    f = from_email.lower()
    if any(s in f for s in EXCLUDE_SENDERS):
        return False
    return any(s in f for s in COMMERCE_SENDERS)


def extract_tracking_number(text):
    text_upper = text.upper()
    m = re.search(r'1Z[A-Z0-9]{16}', text_upper)
    if m:
        return m.group(0), 'UPS'
    m = re.search(r'(?:tracking|tracking\s*#|track\s*#)[:.\s]*([A-Z0-9]{8,30})', text_upper)
    if m:
        tn = m.group(1).strip()
        carrier = 'unknown'
        if 'DHL' in text_upper: carrier = 'DHL'
        elif 'FEDEX' in text_upper: carrier = 'FedEx'
        elif 'UPS' in text_upper: carrier = 'UPS'
        elif 'USPS' in text_upper: carrier = 'USPS'
        return tn, carrier
    return None, None


def extract_order_number(text):
    m = re.search(r' - ([A-Z0-9]{10,20})$', text)
    if m: return m.group(1).strip().upper()
    m = re.search(r'(?:^|[^A-Za-z])#([A-Z0-9]{6,20})(?!\w)', text)
    if m: return m.group(1).strip().upper()
    m = re.search(r'\b([A-Z0-9]*[A-Z][A-Z0-9]{9,19})\b', text)
    if m:
        val = m.group(1).strip().upper()
        skip = {'ORDER', 'CONFIRMATION', 'INVOICE', 'TRACKING', 'SHIPPING', 'DELIVERY', 'PENDING', 'PROCESSING', 'NUMBER', 'REFERENCE'}
        if val not in skip: return val
    return None


def get_tracking_url(carrier, tracking_number):
    if not carrier or not tracking_number: return None
    c = carrier.upper()
    if 'FEDEX' in c: return f'https://www.fedex.com/fedextrack/?trknbr={tracking_number}'
    if 'UPS' in c: return f'https://www.ups.com/track?trackNums={tracking_number}'
    if 'DHL' in c: return None
    if 'USPS' in c: return f'https://www.usps.com/tracking/{tracking_number}'
    if 'CTT' in c or 'CORREIOS' in c: return f'https://www.ctt.pt/track-and-trace?trackingId={tracking_number}'
    if 'DPD' in c: return f'https://tracking.dpd.de/status/en_US/parcel/{tracking_number}'
    if 'GLS' in c: return f'https://gls-group.eu/EN/track-and-trace?match={tracking_number}'
    return None


def upsert_order(order_number, merchant, total, currency, status, source_email_id):
    """Upsert order. Returns order_id."""
    resp = requests.get(
        SUPABASE_BASE + '/orders',
        params={'order_number': f'eq.{order_number}', 'select': 'id'},
        headers=HEADERS, timeout=30
    )
    existing = resp.json()
    if existing:
        order_id = existing[0]['id']
        requests.patch(
            SUPABASE_BASE + '/orders',
            params={'id': f'eq.{order_id}'},
            headers=HEADERS, json={
                'merchant': merchant, 'merchant_name': merchant,
                'normalized_merchant': merchant.lower(), 'status': status,
                'source_email_id': source_email_id,
                'user_id': USER_ID,
            }, timeout=30
        )
        return order_id
    else:
        resp = requests.post(
            SUPABASE_BASE + '/orders',
            headers=HEADERS, json={
                'user_id': USER_ID, 'merchant': merchant, 'merchant_name': merchant,
                'normalized_merchant': merchant.lower(), 'order_number': order_number,
                'total_amount': total, 'currency': currency, 'status': status,
                'source_email_ids': [source_email_id], 'confidence_score': 0.9,
            }, timeout=30
        )
        data = resp.json()
        return (data[0].get('id') if isinstance(data, list) else data.get('id')) if data else None


def upsert_shipment(order_id, tracking_number, carrier, status, source_email_id):
    """Upsert shipment and push delivery record. Returns (shipment_id, was_new)."""
    resp = requests.get(
        SUPABASE_BASE + '/shipments',
        params={'tracking_number': f'eq.{tracking_number}', 'select': 'id'},
        headers=HEADERS, timeout=30
    )
    existing = resp.json()
    if existing:
        return existing[0]['id'], False

    tracking_url = get_tracking_url(carrier, tracking_number)
    shipment_payload = {
        'order_id': order_id, 'tracking_number': tracking_number, 'carrier': carrier,
        'status': status, 'source_email_ids': [source_email_id], 'confidence_score': 0.85,
    }
    if tracking_url:
        shipment_payload['tracking_url'] = tracking_url

    resp = requests.post(
        SUPABASE_BASE + '/shipments',
        headers=HEADERS, json=shipment_payload, timeout=30
    )
    data = resp.json()
    shipment_id = (data[0].get('id') if isinstance(data, list) else data.get('id')) if data else None

    # Push delivery record to dashboard_records
    merchant = carrier or 'Unknown'
    dash_payload = {
        'agent_id': 'orders-autopilot', 'user_id': USER_ID,
        'type': 'delivery', 'category': 'deliveries', 'title': merchant,
        'data': {
            'order_id': order_id, 'carrier': carrier or 'unknown',
            'tracking_number': tracking_number, 'status': 'in_transit' if status != 'delivered' else 'delivered',
            'items': [{'name': merchant, 'quantity': 1}],
            'vendor': merchant, 'tracking_url': tracking_url,
            'delivered': status == 'delivered',
        },
        'display_hint': 'delivery',
    }
    try:
        requests.post(SUPABASE_BASE + '/dashboard_records', headers=HEADERS, json=dash_payload, timeout=30)
    except Exception as e:
        print(f'  Dashboard record error: {e}', file=sys.stderr)

    return shipment_id, True


def main():
    args = sys.argv[1:]
    limit = 60
    lookback_hours = 72
    json_output = '--json' in args

    for i, a in enumerate(args):
        if a == '--limit' and i+1 < len(args): limit = int(args[i+1])
        if a == '--lookback-hours' and i+1 < len(args): lookback_hours = int(args[i+1])

    since = (datetime.now(timezone.utc) - timedelta(hours=lookback_hours)).strftime('%Y-%m-%dT%H:%M:%SZ')

    try:
        token = jc.get_token()
        session = jc.get_session(token)
        account_id = session['accountId']

        all_ids = []
        for mailbox_id in ['P7V', 'P-F']:
            result = jc.jmap_call(session, [
                ['Email/query', {
                    'accountId': account_id,
                    'filter': {'inMailbox': mailbox_id, 'after': since},
                    'sort': [{'property': 'receivedAt', 'isAscending': False}],
                    'limit': limit,
                }, '1'],
            ])
            ids = result[0][1].get('ids', [])
            all_ids.extend(ids)

        unique_ids = list(dict.fromkeys(all_ids))

        if not unique_ids:
            if json_output: print(json.dumps({'orders': 0, 'shipments': 0}))
            else: print('No new emails found.')
            return

        get_result = jc.jmap_call(session, [
            ['Email/get', {
                'accountId': account_id,
                'ids': unique_ids[:limit],
                'properties': ['id', 'subject', 'from', 'receivedAt', 'bodyValues'],
                'fetchTextBodyValues': True,
            }, '2'],
        ])
        emails = get_result[0][1].get('list', [])

    except Exception as e:
        print(f'JMAP error: {e}', file=sys.stderr)
        sys.exit(1)

    orders_created = 0
    shipments_created = 0
    skipped = 0
    errors = 0

    for email in emails:
        email_id = email.get('id')
        subject = email.get('subject', '')
        from_list = email.get('from', [])
        sender = from_list[0].get('email', '') if from_list else ''
        received_at = email.get('receivedAt', '')

        body_values = email.get('bodyValues', {})
        body = ''
        for v in body_values.values():
            if isinstance(v, dict) and v.get('value'):
                body += v['value'] + '\n'

        if not is_commerce_sender(sender) and not is_commerce_sender(subject):
            skipped += 1
            continue

        order_num = extract_order_number(subject + ' ' + body)
        tracking_num, carrier = extract_tracking_number(body)

        status = 'ordered'
        if not order_num and tracking_num:
            status = 'in_transit'

        merchant = sender
        if '@' in merchant:
            domain = merchant.split('@')[1].split('.')[0]
            merchant = domain.title()

        try:
            order_id = None
            if order_num:
                order_id = upsert_order(order_num, merchant, None, 'EUR', status, email_id)
                orders_created += 1

            if tracking_num:
                _, is_new = upsert_shipment(order_id or 'pending', tracking_num, carrier or 'unknown', status, email_id)
                if is_new: shipments_created += 1
        except Exception as e:
            errors += 1
            print(f'Error processing {email_id}: {e}', file=sys.stderr)

    if json_output:
        print(json.dumps({'emails': len(emails), 'orders': orders_created, 'shipments': shipments_created, 'skipped': skipped, 'errors': errors}))
    else:
        print(f'Done. Orders: {orders_created}, Shipments: {shipments_created}, Skipped: {skipped}, Errors: {errors}')


if __name__ == '__main__':
    main()
