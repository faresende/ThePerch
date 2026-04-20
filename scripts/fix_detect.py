#!/usr/bin/env python3
"""Fix detection exclusions in orders_autopilot_ingest_fastmail.py"""

path = '/Users/faresende/.openclaw/workspace/ThePerch/scripts/orders_autopilot_ingest_fastmail.py'
content = open(path).read()

# 1. Replace EXCLUDE_SUBJECT_PATTERNS block with merged EXCLUDE_SUBJECT
old1 = """EXCLUDE_SUBJECT_PATTERNS = [
    r'^unsubscriber', r'^unsubscribe', r'^spam', r'^newsletter',
    r'\\bnewsletter\\b', r'\\bmarketing\\b', r'\\bpromotional\\b', r'\\bpromo\\b',
    r'\\bsale\\b', r'\\bdiscount\\b', r'\\boffer\\b', r'\\bclick\\s+bait\\b',
    r'\\bpassword\\b', r'\\bsign(?:ed)?\\s*in\\b', r'\\balert\\b', r'\\bnotification\\b',
]

# Exclude these senders regardless of content
EXCLUDE_SENDERS = [
    'glovo', 'uber', 'bolt', 'freenow', 'taxis', 'lyft', 'deliveroo', 'just eat',
    'net-a-porter', 'restaurante', 'restaurant', 'food', 'pizza', 'sushi',
    'bolha', 'mcdonald', 'kfc', 'subway', 'starbucks',
    'no-reply', 'noreply', 'dontreply', 'donotreply',
    'amazon.nl', 'amazon.de', 'amazon.es', 'amazon.fr',
]

# Exclude subjects that look like notifications, not orders
EXCLUDE_SUBJECT = [
    r'\\bdhl\\s+on\\s+demand\\b', r'\\bdhl\\s+odd\\b',
    r'^email\\s*$', r'^message\\s*$',
]"""

new1 = """# Exclude subjects that look like notifications, not orders
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
]"""

if old1 in content:
    content = content.replace(old1, new1)
    print("Replaced exclusion blocks")
else:
    print("ERROR: old1 not found!")
    # Find what's actually there
    idx = content.find("EXCLUDE_SUBJECT_PATTERNS")
    if idx >= 0:
        print("Found EXCLUDE_SUBJECT_PATTERNS at index", idx)
        print(repr(content[idx:idx+500]))

open(path, 'w').write(content)
print("Done")
