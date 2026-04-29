const pageUrl = document.getElementById('page-url');
const pageTitle = document.getElementById('page-title');
const tagsInput = document.getElementById('tags');
const form = document.getElementById('bookmark-form');
const statusDiv = document.getElementById('status');
const setupNotice = document.getElementById('setup-notice');
const openOptionsLink = document.getElementById('open-options');

let currentTab = null;

// Extract domain from URL
function extractDomain(url) {
  try {
    const urlObj = new URL(url);
    return urlObj.hostname || 'unknown';
  } catch {
    return 'unknown';
  }
}

// Show status message
//
// Round 9 audit (HIGH): the prior implementation used .innerHTML for the
// error path with `${message}` interpolation. `message` traces back to
// server response statusText / error.message — server-controlled if the
// configured Supabase URL is ever attacker-controlled or compromised.
// XSS in the popup origin yields chrome.storage + chrome.tabs access.
// Replaced with createElement so the message is always set as text.
function showStatus(type, message) {
  statusDiv.className = `status show ${type}`;
  statusDiv.textContent = '';
  statusDiv.appendChild(document.createTextNode(message));
  if (type === 'error') {
    const sub = document.createElement('div');
    sub.className = 'error-message';
    sub.textContent = 'Check extension options for configuration.';
    statusDiv.appendChild(sub);
  }
}

// Initialize popup
async function init() {
  // Get current tab info
  const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
  if (tabs.length === 0) {
    showStatus('error', 'Could not get active tab');
    return;
  }

  currentTab = tabs[0];
  pageUrl.value = currentTab.url || '';
  pageTitle.textContent = currentTab.title || 'Untitled';

  // Check if configured
  const { supabaseUrl, supabaseKey, authToken } = await chrome.storage.local.get([
    'supabaseUrl',
    'supabaseKey',
    'authToken'
  ]);

  if (!supabaseUrl || !supabaseKey || !authToken) {
    setupNotice.style.display = 'block';
    form.style.display = 'none';
    return;
  }

  form.style.display = 'flex';
  setupNotice.style.display = 'none';
}

// Handle save
form.addEventListener('submit', async (e) => {
  e.preventDefault();

  const url = pageUrl.value;
  const title = pageTitle.textContent;
  const tags = tagsInput.value.split(',').map(t => t.trim()).filter(Boolean);

  // Get config
  const { supabaseUrl, supabaseKey, authToken } = await chrome.storage.local.get([
    'supabaseUrl',
    'supabaseKey',
    'authToken'
  ]);

  if (!supabaseUrl || !supabaseKey || !authToken) {
    showStatus('error', 'Configuration missing');
    return;
  }

  showStatus('saving', 'Saving...');

  try {
    const domain = extractDomain(url);

    // Insert into bookmarks table
    const bookmarkResponse = await fetch(`${supabaseUrl}/rest/v1/bookmarks`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': supabaseKey,
        'Authorization': `Bearer ${authToken}`
      },
      body: JSON.stringify({
        url,
        title,
        tags,
        domain,
        status: 'pending',
        created_at: new Date().toISOString()
      })
    });

    if (!bookmarkResponse.ok) {
      const error = await bookmarkResponse.text();
      console.error('Bookmark insert error:', error);
      throw new Error(`Failed to save bookmark: ${bookmarkResponse.statusText}`);
    }

    const bookmarkData = await bookmarkResponse.json();
    const bookmarkId = bookmarkData[0]?.id;

    if (!bookmarkId) {
      throw new Error('No bookmark ID returned');
    }

    // Insert into dashboard_records table
    const recordResponse = await fetch(`${supabaseUrl}/rest/v1/dashboard_records`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': supabaseKey,
        'Authorization': `Bearer ${authToken}`
      },
      body: JSON.stringify({
        type: 'bookmark',
        category: 'bookmarks',
        bookmark_id: bookmarkId,
        created_at: new Date().toISOString()
      })
    });

    if (!recordResponse.ok) {
      const error = await recordResponse.text();
      console.error('Record insert error:', error);
      throw new Error(`Failed to create record: ${recordResponse.statusText}`);
    }

    showStatus('success', '✓ Saved! Closing in 1.5s...');

    // Auto-close popup after 1.5 seconds
    setTimeout(() => {
      window.close();
    }, 1500);
  } catch (error) {
    console.error('Save error:', error);
    showStatus('error', error.message || 'Failed to save bookmark');
  }
});

// Handle options link
openOptionsLink.addEventListener('click', (e) => {
  e.preventDefault();
  chrome.runtime.openOptionsPage();
});

// Initialize on load
init();
