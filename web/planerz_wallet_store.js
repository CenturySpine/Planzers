'use strict';

// On-device copies of "Mes documents" files, for offline access.
//
// Stored in the app's own IndexedDB database (invisible to the user, no
// download folder involved), keyed "<uid>/<tripId>/<documentId>".
(function () {
  var DB_NAME = 'planerz-wallet';
  var STORE = 'files';
  var dbPromise = null;

  function openDb() {
    if (dbPromise) return dbPromise;
    dbPromise = new Promise(function (resolve, reject) {
      var request = indexedDB.open(DB_NAME, 1);
      request.onupgradeneeded = function () {
        request.result.createObjectStore(STORE);
      };
      request.onsuccess = function () {
        resolve(request.result);
      };
      request.onerror = function () {
        dbPromise = null;
        reject(request.error);
      };
    });
    return dbPromise;
  }

  function run(mode, action) {
    return openDb().then(function (db) {
      return new Promise(function (resolve, reject) {
        var transaction = db.transaction(STORE, mode);
        var request = action(transaction.objectStore(STORE));
        transaction.oncomplete = function () {
          resolve(request ? request.result : undefined);
        };
        transaction.onerror = function () {
          reject(transaction.error);
        };
        transaction.onabort = function () {
          reject(transaction.error);
        };
      });
    });
  }

  function prefixRange(prefix) {
    return IDBKeyRange.bound(prefix, prefix + '￿');
  }

  window.planerzWalletStore = {
    save: function (key, bytes) {
      // Copy into a standalone buffer: the Dart view may share a larger one.
      var copy = bytes.slice().buffer;
      return run('readwrite', function (store) {
        return store.put(copy, key);
      });
    },
    read: function (key) {
      return run('readonly', function (store) {
        return store.get(key);
      }).then(function (buffer) {
        return buffer ? new Uint8Array(buffer) : null;
      });
    },
    keys: function (prefix) {
      return run('readonly', function (store) {
        return store.getAllKeys(prefixRange(prefix));
      });
    },
    remove: function (key) {
      return run('readwrite', function (store) {
        return store.delete(key);
      });
    },
    removePrefix: function (prefix) {
      return run('readwrite', function (store) {
        return store.delete(prefixRange(prefix));
      });
    },
    // Asks the browser not to evict this data under storage pressure; the
    // browser decides (Safari mostly grants it to installed web apps).
    requestPersistence: function () {
      if (!navigator.storage || !navigator.storage.persist) {
        return Promise.resolve(false);
      }
      return navigator.storage.persist().catch(function () {
        return false;
      });
    },
    // Fetches files once while online so the offline worker keeps them
    // (e.g. the PDF viewer engine, only loaded when a PDF is first shown).
    warmUp: function (urls) {
      return Promise.all(
        urls.map(function (url) {
          return fetch(url).catch(function () {});
        }),
      ).then(function () {});
    },
  };
})();
