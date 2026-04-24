-- Add tracking_url column for carrier-specific tracking links
ALTER TABLE shipments ADD COLUMN IF NOT EXISTS tracking_url text;

-- Backfill: set tracking_url based on carrier + tracking_number for known carriers
UPDATE shipments SET tracking_url = 'https://www.fedex.com/fedextrack/?trknbr=' || tracking_number
WHERE carrier ILIKE '%fedex%' AND tracking_number IS NOT NULL AND tracking_url IS NULL;

UPDATE shipments SET tracking_url = 'https://www.dhl.com/de-en/home/tracking/tracking-parcel.html?submit=1&trackingID=' || tracking_number
WHERE carrier ILIKE '%dhl%' AND tracking_number IS NOT NULL AND tracking_url IS NULL;

UPDATE shipments SET tracking_url = 'https://www.ups.com/track?trackNums=' || tracking_number
WHERE carrier ILIKE '%ups%' AND tracking_number IS NOT NULL AND tracking_url IS NULL;

UPDATE shipments SET tracking_url = 'https://www.ctt.pt/track-and-trace?trackingId=' || tracking_number
WHERE (carrier ILIKE '%ctt%' OR carrier ILIKE '%ctt express%' OR carrier ILIKE '%correios%') AND tracking_number IS NOT NULL AND tracking_url IS NULL;

UPDATE shipments SET tracking_url = 'https://www.usps.com/tracking/' || tracking_number
WHERE carrier ILIKE '%usps%' AND tracking_number IS NOT NULL AND tracking_url IS NULL;

UPDATE shipments SET tracking_url = 'https://tracking.t-mobile.com/m/p/' || tracking_number
WHERE carrier ILIKE '%t-mobile%' AND tracking_number IS NOT NULL AND tracking_url IS NULL;
