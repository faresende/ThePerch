content = open('/Users/faresende/.openclaw/workspace/ThePerch/scripts/orders_autopilot_ingest_fastmail.py').read()

# Add more specific sender exclusions
old = "    'amazon.nl', 'amazon.de', 'amazon.es', 'amazon.fr',\n]"
new = "    'amazon.nl', 'amazon.de', 'amazon.es', 'amazon.fr',\n    'paypal.com', 'service@paypal',\n    'sendcloud.com',\n    'loox.io',\n    'email.apple.com',\n]"
content = content.replace(old, new)

# Add subject exclusions for review reminders
old2 = "EXCLUDE_SUBJECT = [\n    r'\\bdhl\\s+on\\s+demand\\b', r'\\bdhl\\s+odd\\b',\n    r'^email\\s*$', r'^message\\s*$',\n]"
new2 = "EXCLUDE_SUBJECT = [\n    r'\\bdhl\\s+on\\s+demand\\b', r'\\bdhl\\s+odd\\b',\n    r'^email\\s*$', r'^message\\s*$',\n    r'\\breminder\\b', r'\\breview\\b',\n    r'\\byour\\s+receipt\\b',\n]"
content = content.replace(old2, new2)

open('orders_autopilot_ingest_fastmail.py', 'w').write(content)
print('Done')
