/* eslint-disable no-undef */
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

const prodConfig = {
  apiKey: 'AIzaSyDXFZrpXlQa1_FqNmbTVUsOlTcHDcs3pPU',
  appId: '1:936277491452:web:1794a04a8c81d6f8f1e179',
  messagingSenderId: '936277491452',
  projectId: 'planzers',
  authDomain: 'planzers.firebaseapp.com',
  storageBucket: 'planzers.firebasestorage.app',
  measurementId: 'G-Z68T9LKMH7',
};

const previewConfig = {
  apiKey: 'AIzaSyA84GI-A3YJGUGnT6XPGa8VZ4NSKSJKsXQ',
  appId: '1:426381891835:web:26bade9d1738a1e419785e',
  messagingSenderId: '426381891835',
  projectId: 'planzers-preview',
  authDomain: 'planzers-preview.firebaseapp.com',
  storageBucket: 'planzers-preview.firebasestorage.app',
};

const host = self.location.hostname || '';
const usePreview = host.includes('preview');
firebase.initializeApp(usePreview ? previewConfig : prodConfig);

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const notification = payload.notification || {};
  const data = payload.data || {};
  const title = notification.title || 'Planzers';
  const body = notification.body || '';
  const tripId = typeof data.tripId === 'string' ? data.tripId.trim() : '';
  const type = typeof data.type === 'string' ? data.type.trim() : '';
  const targetPath =
    type === 'trip_message' && tripId ? `/trips/${tripId}/messages` : '/trips';

  self.registration.showNotification(title, {
    body,
    data: {
      url: targetPath,
    },
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
