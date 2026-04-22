/* eslint-disable no-undef */
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

const prodConfig = {
  apiKey: 'AIzaSyC6N9_UQcpIiXNAh9VxlwYmYoYgw5L_WqM',
  appId: '1:968267093466:web:fe185a5604145fe3d29ce3',
  messagingSenderId: '968267093466',
  projectId: 'planerz',
  authDomain: 'planerz.firebaseapp.com',
  storageBucket: 'planerz.firebasestorage.app',
  measurementId: 'G-MDP337D1C0',
};

const previewConfig = {
  apiKey: 'AIzaSyCh1WtquB9vido6MZDLAPdAA0TqDCqVYWk',
  appId: '1:1072541832110:web:bb11a3f3bde9fbfe546e3f',
  messagingSenderId: '1072541832110',
  projectId: 'planerz-preview',
  authDomain: 'planerz-preview.firebaseapp.com',
  storageBucket: 'planerz-preview.firebasestorage.app',
  measurementId: 'G-8X0K4KJR7R',
};

const host = self.location.hostname || '';
const usePreview = host.includes('preview');
firebase.initializeApp(usePreview ? previewConfig : prodConfig);

const messaging = firebase.messaging();

messaging.onBackgroundMessage(async (payload) => {
  // Suppress system notification when the PWA window is already visible —
  // the Flutter app handles foreground messages itself via onMessage.
  const clients = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
  if (clients.some((c) => c.visibilityState === 'visible')) return;

  const notification = payload.notification || {};
  const data = payload.data || {};
  const title = notification.title || 'Planerz';
  const body = notification.body || '';
  const tripId = typeof data.tripId === 'string' ? data.tripId.trim() : '';
  const type = typeof data.type === 'string' ? data.type.trim() : '';
  const targetPathRaw =
    typeof data.targetPath === 'string' ? data.targetPath.trim() : '';
  const targetPath = targetPathRaw
    ? targetPathRaw
    : (type === 'trip_message' && tripId ? `/trips/${tripId}/messages` : '/trips');

  self.registration.showNotification(title, {
    body,
    data: { url: targetPath },
  });
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const targetUrl =
    typeof event.notification.data?.url === 'string'
      ? event.notification.data.url
      : '/trips';

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clients) => {
      for (const client of clients) {
        if ('focus' in client) {
          client.navigate(targetUrl);
          return client.focus();
        }
      }
      if (self.clients.openWindow) {
        return self.clients.openWindow(targetUrl);
      }
      return undefined;
    }),
  );
});
