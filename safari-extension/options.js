const form = document.getElementById('settings-form');
const supabaseUrlInput = document.getElementById('supabase-url');
const supabaseKeyInput = document.getElementById('supabase-key');
const authTokenInput = document.getElementById('auth-token');
const clearBtn = document.getElementById('clear-btn');
const statusDiv = document.getElementById('status');

function showStatus(type, message) {
  statusDiv.className = `status show ${type}`;
  statusDiv.textContent = message;
  setTimeout(() => {
    statusDiv.classList.remove('show');
  }, 3000);
}

// Load saved settings on page load
async function loadSettings() {
  const settings = await chrome.storage.sync.get([
    'supabaseUrl',
    'supabaseKey',
    'authToken'
  ]);

  if (settings.supabaseUrl) {
    supabaseUrlInput.value = settings.supabaseUrl;
  }
  if (settings.supabaseKey) {
    supabaseKeyInput.value = settings.supabaseKey;
  }
  if (settings.authToken) {
    authTokenInput.value = settings.authToken;
  }
}

// Save settings
form.addEventListener('submit', async (e) => {
  e.preventDefault();

  const supabaseUrl = supabaseUrlInput.value.trim();
  const supabaseKey = supabaseKeyInput.value.trim();
  const authToken = authTokenInput.value.trim();

  if (!supabaseUrl || !supabaseKey || !authToken) {
    showStatus('error', 'All fields are required');
    return;
  }

  // Validate URL format
  try {
    new URL(supabaseUrl);
  } catch {
    showStatus('error', 'Invalid Supabase URL format');
    return;
  }

  await chrome.storage.sync.set({
    supabaseUrl,
    supabaseKey,
    authToken
  });

  showStatus('success', '✓ Settings saved successfully');
});

// Clear all settings
clearBtn.addEventListener('click', async () => {
  if (confirm('Are you sure you want to clear all settings?')) {
    await chrome.storage.sync.remove([
      'supabaseUrl',
      'supabaseKey',
      'authToken'
    ]);

    supabaseUrlInput.value = '';
    supabaseKeyInput.value = '';
    authTokenInput.value = '';

    showStatus('success', 'Settings cleared');
  }
});

// Load settings when page opens
loadSettings();
