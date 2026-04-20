#!/usr/bin/env python3
"""
orders_autopilot_ingest_fastmail.py
Fetches recent commerce emails from Fastmail (Paper Trail + Inbox),
detects order emails by content patterns (not sender whitelist),
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

# Patterns that indicate an order/commerce email (subject or body)
ORDER_SUBJECT_PATTERNS = [
    # English
    r'\border\b', r'\bordering\b', r'\border\s+confirmation\b', r'\border\s+received\b',
    r'\bconfirmation\b', r'\bconfirmed\b', r'\bshipped\b', r'\bshipping\b',
    r'\bdelivered\b', r'\bdelivery\b', r'\btracking\b', r'\btrack(?:ing)?\s*(?:number|id|#)\b',
    r'\bin\s+transit\b', r'\bout\s+for\s+delivery\b',
    r'\binvoice\b', r'\bfatura\b', r'\breceipt\b', r'\bpurchase\b',
    r'\bpackage\b', r'\bparcel\b',
    # Portuguese
    r'\bencomenda\b', r'\bconfirmação\b', r'\bconfirma\b', r'\bpedido\b',
    r'\benviado\b', r'\bentregue\b', r'\bfatura\b', r'\brecibo\b',
    # Dutch
    r'\bbestelling\b', r'\bbestätigung\b', r'\bverzonden\b', r'\bgeleverd\b',
    # German
    r'\bbestellung\b', r'\bversandt\b', r'\blieferung\b',
    # Generic signals
    r'\border\s*#', r'\borden\s*#', r'\bpedido\s*#', r'\btracking\s*:',
    r'\bupcoming\s+delivery\b', r'\byour\s+order\b', r'\byour\s+package\b',
]

# Patterns that indicate this is NOT an order email (exclude)
# Exclude subjects that look like notifications, not orders
EXCLUDE_SUBJECT = [
    # Newsletter/marketing
    r"^unsubscriber", r"^unsubscribe", r"^spam", r"^newsletter",
    r"\bnewsletter\b", r"\bmarketing\b", r"\bpromotional\b", r"\bpromo\b",
    r"\bsale\b", r"\bdiscount\b", r"\boffer\b", r"\bclick\s+bait\b",
    r"\bpassword\b", r"\bsign(?:ed)?\s*in\b",
    # Logistics/service
    r"\bdhl\s+on\s+demand\b", r"\bdhl\s+odd\b",
    r"^email\s*$", r"^message\s*$",
    # Review/reminder
    r"\breminder\b", r"\breview\b",
    r"\byour\s+receipt\b",
]

# Exclude these senders regardless of content
EXCLUDE_SENDERS = [
    "glovo", "uber", "bolt", "freenow", "taxis", "lyft", "deliveroo", "just eat",
    "net-a-porter", "restaurante", "restaurant", "food", "pizza", "sushi",
    "bolha", "mcdonald", "kfc", "subway", "starbucks",
    "no-reply", "noreply", "dontreply", "donotreply",
    "amazon.nl", "amazon.de", "amazon.es", "amazon.fr",
    "paypal.com", "service@paypal",
    "sendcloud.com",
    "loox.io",
    "email.apple.com",
]

STRONG_ORDER_SIGNALS = [
    r'\border\b', r'\bencomenda\b', r'\bconfirmação\b', r'\bconfirma\b',
    r'\bpedido\b', r'\bfatura\b', r'\bpedido\b', r'\bordering\b',
    r'\border\s+confirmation\b', r'\border\s+received\b',
    r'\border\s+#', r'\bordered\s+#',
    r'\binvoice\b', r'\breceipt\b', r'\bpurchase\b',
    r'\bupcoming\s+delivery\b', r'\byour\s+order\b', r'\byour\s+package\b',
]

# Weak order signals — need at least one strong signal or a tracking number
WEAK_ORDER_SIGNALS = [
    r'\bshipped\b', r'\bshipping\b', r'\bdispatched\b',
    r'\bdelivered\b', r'\bpackage\b', r'\bparcel\b',
    r'\bout\s+for\s+delivery\b', r'\btracking\b',
    r'\bin\s+transit\b', r'\benviado\b', r'\bentregue\b', r'\bverzonden\b',
    r'\bgeliefert\b', r'\bversandt\b',
]


def matches_any(text, patterns):
    t = text.lower()
    return any(re.search(p, t) for p in patterns)


def is_order_email(subject, body, from_email):
    """Detect if an email is an order/shipping confirmation by content, not sender."""
    f = from_email.lower()

    # Always exclude certain senders
    for exc in EXCLUDE_SENDERS:
        if exc in f:
            return False

    subject_lower = subject.lower()
    body_lower = body.lower()
    combined = subject_lower + ' ' + body_lower

    # Must have at least one strong order signal
    has_strong = matches_any(subject_lower, STRONG_ORDER_SIGNALS)
    has_weak = matches_any(combined, WEAK_ORDER_SIGNALS)

    # Strong signal in subject = order
    if has_strong:
        # Exclude logistics/service emails that happen to have order in subject
        if matches_any(subject_lower, EXCLUDE_SUBJECT):
            return False
        return True

    # Weak-only signals need more: must have a tracking number or order number
    if has_weak:
        tracking_num, _ = extract_tracking_number(body)
        order_num = extract_order_number(subject + ' ' + body)
        if tracking_num or order_num:
            return True

    return False


def infer_order_status(subject, body, has_tracking, has_order_number):
    """Infer order status from email content."""
    text = (subject + ' ' + body).lower()

    if has_tracking and ('delivered' in text or 'entregue' in text or 'geleverd' in text):
        return 'delivered'
    if has_tracking and ('shipped' in text or 'enviado' in text or 'versandt' in text or 'verzonden' in text or 'on its way' in text or 'dispatched' in text):
        return 'shipped'
    if has_tracking and ('out for delivery' in text or 'entrega' in text or 'out for delivery' in text):
        return 'out_for_delivery'
    if has_tracking and ('in transit' in text or 'transit' in text or 'em trânsito' in text):
        return 'in_transit'
    if has_tracking:
        return 'shipped'  # assume shipped once tracking exists
    if has_order_number:
        return 'ordered'
    return 'ordered'


def extract_tracking_number(text):
    text_upper = text.upper()
    # UPS 1Z format
    m = re.search(r'1Z[A-Z0-9]{16}', text_upper)
    if m:
        return m.group(0), 'UPS'
    # DHL numeric
    m = re.search(r'(?<!\d)\d{10,15}(?!\d)', text)
    if m:
        tn = m.group(0)
        if 'DHL' in text_upper: return tn, 'DHL'
    # Generic tracking patterns
    m = re.search(r'(?:tracking|tracking\s*#|track\s*#|tracking-id|trknr)[:.\s]*([A-Z0-9]{6,30})', text_upper)
    if m:
        tn = m.group(1).strip().replace(' ', '')
        if len(tn) >= 6:
            carrier = 'unknown'
            if 'DHL' in text_upper: carrier = 'DHL'
            elif 'FEDEX' in text_upper or 'FED EX' in text_upper: carrier = 'FedEx'
            elif 'UPS' in text_upper: carrier = 'UPS'
            elif 'USPS' in text_upper: carrier = 'USPS'
            elif 'GLS' in text_upper: carrier = 'GLS'
            elif 'DPD' in text_upper: carrier = 'DPD'
            elif 'CTT' in text_upper or 'CORREIOS' in text_upper: carrier = 'CTT'
            return tn, carrier
    return None, None


def extract_order_number(text):
    m = re.search(r' - ([A-Z0-9]{10,20})$', text)
    if m: return m.group(1).strip().upper()
    m = re.search(r'(?:^|[^A-Za-z])#([A-Z0-9]{8,20})(?!\w)', text)
    if m: return m.group(1).strip().upper()
    m = re.search(r'\b([A-Z0-9]*[A-Z][A-Z0-9]{11,19})\b', text)
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
    if 'DHL' in c: return f'https://www.dhl.com/pt-en/home/tracking.html?tracking-id={tracking_number}&submit=1'
    if 'USPS' in c: return f'https://www.usps.com/tracking/{tracking_number}'
    if 'CTT' in c or 'CORREIOS' in c: return f'https://www.ctt.pt/track-and-trace?trackingId={tracking_number}'
    if 'DPD' in c: return f'https://tracking.dpd.de/status/en_US/parcel/{tracking_number}'
    if 'GLS' in c: return f'https://gls-group.eu/EN/track-and-trace?match={tracking_number}'
    return None


def upsert_delivery_record(order_id, merchant, status, tracking_number=None, carrier=None, tracking_url=None, source_email_id=None):
    """Create or update a delivery record for an order in dashboard_records."""
    delivered = status == 'delivered'
    data = {
        'order_id': order_id,
        'carrier': carrier or 'unknown',
        'status': status,
        'vendor': merchant,
        'delivered': delivered,
    }
    if tracking_number:
        data['tracking_number'] = tracking_number
    if tracking_url:
        data['tracking_url'] = tracking_url
    if carrier:
        data['items'] = [{'name': merchant, 'quantity': 1}]

    dash_payload = {
        'agent_id': 'claudinho',
        'user_id': USER_ID,
        'type': 'delivery',
        'category': 'deliveries',
        'title': merchant,
        'data': data,
        'display_hint': 'delivery',
    }

    # Try to find existing delivery record for this order
    try:
        resp = requests.get(
            SUPABASE_BASE + '/dashboard_records',
            params={
                'order_id': f'eq.{order_id}',
                'category': 'eq.deliveries',
                'select': 'id',
                'limit': 1,
            },
            headers=HEADERS, timeout=30
        )
        existing = resp.json()
        if existing:
            # Update existing
            requests.patch(
                SUPABASE_BASE + '/dashboard_records',
                params={'id': f'eq.{existing[0]["id"]}'},
                headers=HEADERS, json={'data': data, 'title': merchant}, timeout=30
            )
            return existing[0]['id'], False
    except: pass

    # Create new
    try:
        resp = requests.post(
            SUPABASE_BASE + '/dashboard_records',
            headers=HEADERS, json=dash_payload, timeout=30
        )
        data_resp = resp.json()
        return (data_resp[0].get('id') if isinstance(data_resp, list) else data_resp.get('id')), True
    except Exception as e:
        print(f'  Delivery record error: {e}', file=sys.stderr)
        return None, True


def upsert_order(order_number, merchant, total, currency, status, source_email_id, from_email):
    """Upsert order. If order_number is None, upserts by merchant+email combo."""
    order_id = None

    if order_number:
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
                    'status': status, 'source_email_id': source_email_id,
                }, timeout=30
            )
            return order_id

    # No order number or not found — upsert by normalized_merchant + recent
    norm = merchant.lower()
    # Try to find existing pending/procssing order from same merchant (within 30 days)
    try:
        resp = requests.get(
            SUPABASE_BASE + '/orders',
            params={
                'normalized_merchant': f'eq.{norm}',
                'status': 'in.(ordered,processing)',
                'select': 'id,created_at',
                'order': 'created_at.desc',
                'limit': 1,
            },
            headers=HEADERS, timeout=30
        )
        existing = resp.json()
        if existing:
            order_id = existing[0]['id']
            requests.patch(
                SUPABASE_BASE + '/orders',
                params={'id': f'eq.{order_id}'},
                headers=HEADERS, json={'status': status, 'source_email_id': source_email_id}, timeout=30
            )
            return order_id
    except: pass

    # Create new order (order_number may be None for new-vendor PDFs)
    payload = {
        'user_id': USER_ID, 'merchant': merchant, 'merchant_name': merchant,
        'normalized_merchant': norm, 'order_number': order_number,
        'total_amount': total, 'currency': currency or 'EUR', 'status': status,
        'source_email_ids': [source_email_id], 'source_email_id': source_email_id,
        'confidence_score': 0.75,
    }
    resp = requests.post(
        SUPABASE_BASE + '/orders',
        headers=HEADERS, json=payload, timeout=30
    )
    data = resp.json()
    if data:
        order_id = (data[0].get('id') if isinstance(data, list) else data.get('id')) if data else None
    else:
        order_id = None

    # Always create/update delivery record for the order
    if order_id:
        upsert_delivery_record(order_id, merchant, status, source_email_id=source_email_id)

    return order_id


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

    # Update delivery record with tracking info
    if order_id and order_id != 'pending':
        upsert_delivery_record(order_id, carrier or 'Unknown', status,
                               tracking_number=tracking_number, carrier=carrier,
                               tracking_url=tracking_url, source_email_id=source_email_id)

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
            if json_output: print(json.dumps({'emails': 0, 'orders': 0, 'shipments': 0, 'skipped': 0, 'errors': 0}))
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

        body_values = email.get('bodyValues', {})
        body = ''
        for v in body_values.values():
            if isinstance(v, dict) and v.get('value'):
                body += v['value'] + '\n'

        # Content-based detection (replaces sender whitelist)
        if not is_order_email(subject, body, sender):
            skipped += 1
            continue

        order_num = extract_order_number(subject + ' ' + body)
        tracking_num, carrier = extract_tracking_number(body)

        status = infer_order_status(subject, body, bool(tracking_num), bool(order_num))

        merchant = sender
        if '@' in merchant:
            domain = merchant.split('@')[1].split('.')[0]
            merchant = domain.title()

        try:
            order_id = upsert_order(order_num, merchant, None, 'EUR', status, email_id, sender)
            if order_id:
                orders_created += 1

            if tracking_num and order_id:
                _, is_new = upsert_shipment(order_id, tracking_num, carrier or 'unknown', status, email_id)
                if is_new: shipments_created += 1
        except Exception as e:
            errors += 1
            print(f'Error processing {email_id}: {e}', file=sys.stderr)

    if json_output:
        print(json.dumps({
            'emails': len(emails),
            'orders': orders_created,
            'shipments': shipments_created,
            'skipped': skipped,
            'errors': errors,
        }))
    else:
        print(f'Done. Orders: {orders_created}, Shipments: {shipments_created}, Skipped: {skipped}, Errors: {errors}')


if __name__ == '__main__':
    main()
