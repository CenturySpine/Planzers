'use strict';

// Offline support for the Planerz web app.
//
// Flutter no longer ships a caching service worker, so this one keeps a copy
// of everything needed to boot the app (index, compiled Dart, engine, assets,
// Firebase JS SDK, fonts) and serves it when the network is unavailable.
//
// Strategy:
// - App files (same origin, not content-hashed): network first, so an online
//   user always gets the latest deployed version; the cached copy is only used
//   when the network fails or is too slow.
// - Versioned third-party files (engine, Firebase SDK, fonts): cache first,
//   their URLs change with every version.
// - Everything else (Firestore, Auth, Storage, Functions APIs) is never
//   intercepted: data offline is handled by the Firestore cache.

const CACHE_PREFIX = 'planerz-offline-';
const CACHE_NAME = `${CACHE_PREFIX}v1`;
const NETWORK_TIMEOUT_MS = 6000;
const APP_SHELL_URL = new URL('./', self.registration.scope).href;
const CORE_FILES = ['./', 'flutter_bootstrap.js', 'main.dart.js', 'manifest.json'];
const VERSIONED_CDN_HOSTS = [
  'www.gstatic.com',
  'fonts.gstatic.com',
  'cdnjs.cloudflare.com',
];
const EXCLUDED_PATHS = ['/sw.js', '/firebase-messaging-sw.js'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE_NAME);
      await Promise.all(
        CORE_FILES.map((file) =>
          storeIfMissing(cache, new URL(file, self.registration.scope).href),
        ),
      );
      await self.skipWaiting();
    })(),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const names = await caches.keys();
      await Promise.all(
        names
          .filter((name) => name.startsWith(CACHE_PREFIX) && name !== CACHE_NAME)
          .map((name) => caches.delete(name)),
      );
      await self.clients.claim();
    })(),
  );
});

// The page sends the resources it loaded before this worker controlled it,
// so a single online visit is enough to work offline afterwards.
self.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.type !== 'precache' || !Array.isArray(data.urls)) return;
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE_NAME);
      await Promise.all(
        data.urls
          .filter((url) => typeof url === 'string' && isCacheable(new URL(url)))
          .map((url) => storeIfMissing(cache, url)),
      );
    })(),
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);

  if (request.mode === 'navigate') {
    if (url.origin !== self.location.origin || url.pathname.startsWith('/__/')) {
      return;
    }
    // Single-page app: every route is served by the same index.html.
    event.respondWith(networkFirst(request, APP_SHELL_URL));
    return;
  }

  if (!isCacheable(url)) return;
  if (url.origin === self.location.origin) {
    event.respondWith(networkFirst(request, cacheKeyFor(url)));
  } else {
    event.respondWith(cacheFirst(request));
  }
});

function isCacheable(url) {
  if (url.origin === self.location.origin) {
    return (
      !url.pathname.startsWith('/__/') && !EXCLUDED_PATHS.includes(url.pathname)
    );
  }
  return url.protocol === 'https:' && VERSIONED_CDN_HOSTS.includes(url.hostname);
}

// App files are not content-hashed: ignore cache-busting query strings so a
// single entry per file is kept and refreshed.
function cacheKeyFor(url) {
  return url.origin === self.location.origin ? url.origin + url.pathname : url.href;
}

async function storeIfMissing(cache, href) {
  const url = new URL(href);
  const key = cacheKeyFor(url);
  try {
    if (await cache.match(key)) return;
    // CORS mode keeps the stored copy readable by any later request for it
    // (an opaque copy would break engine and Firebase SDK module loads).
    const response = await fetch(href, { mode: 'cors' });
    if (response.ok) await cache.put(key, response);
  } catch (_) {
    // Best effort: the file will be cached the next time it is requested.
  }
}

async function networkFirst(request, cacheKey) {
  const cache = await caches.open(CACHE_NAME);
  const cached = await cache.match(cacheKey);
  const network = fetch(request).then(async (response) => {
    if (response.ok) await cache.put(cacheKey, response.clone());
    return response;
  });
  if (!cached) return network;
  try {
    return await withTimeout(network, NETWORK_TIMEOUT_MS);
  } catch (_) {
    // Offline or too slow: the network request keeps running in the
    // background and refreshes the cache if it eventually succeeds.
    network.catch(() => {});
    return cached;
  }
}

async function cacheFirst(request) {
  const cache = await caches.open(CACHE_NAME);
  const cached = await cache.match(request.url);
  if (cached) return cached;
  const response = await fetch(request);
  // Opaque (no-cors) responses are not stored: see storeIfMissing.
  if (response.ok) await cache.put(request.url, response.clone());
  return response;
}

function withTimeout(promise, ms) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('timeout')), ms);
    promise.then(
      (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      (error) => {
        clearTimeout(timer);
        reject(error);
      },
    );
  });
}
