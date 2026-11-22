// v2 TEST version: points to the TEST Supabase project (DMC-Curve-Progress-v2-Test).
// The live app (branch main) keeps its own config.js pointing to the live database.
// The publishable key is safe to publish — the database is protected by Row Level Security.
// NEVER put a secret (sb_secret_...) or service_role key here.
window.DMC_CONFIG = {
  SUPABASE_URL: "https://kgqashsqpmacwxyolfjs.supabase.co",
  SUPABASE_ANON_KEY: "sb_publishable_M-qJWUU3Ny9HPe4d0iBmfA_nUvLn1sC",
  ENV: "test"
};
// Small "TEST v2" badge so nobody confuses this with the live app.
(function () {
  function add() {
    if (document.getElementById('dmc-test-badge')) return;
    var b = document.createElement('div');
    b.id = 'dmc-test-badge';
    b.textContent = 'TEST v2 · نسخة تجريبية';
    b.setAttribute('style', 'position:fixed;top:0;left:50%;transform:translateX(-50%);z-index:2147483647;background:#c0392b;color:#fff;font:700 11px/1 sans-serif;padding:4px 10px;border-radius:0 0 8px 8px;pointer-events:none;opacity:.92');
    document.body.appendChild(b);
  }
  if (document.body) add(); else document.addEventListener('DOMContentLoaded', add);
})();
