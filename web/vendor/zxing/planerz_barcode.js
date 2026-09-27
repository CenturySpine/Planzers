'use strict';

// Barcode decoding helpers for the wallet ("Mes documents").
//
// The ZXing library (Apache 2.0, see LICENSE) is served by the app itself so
// it is cached for offline use, and loaded only when first needed. The
// script id is the one mobile_scanner looks for: the live camera scanner then
// reuses this copy instead of fetching its own from a CDN.
(function () {
  var ZXING_SRC = 'vendor/zxing/zxing-library-0.23.0.min.js';
  var ZXING_SCRIPT_ID = 'mobile-scanner-zxing-js';
  var loading = null;

  function ensureLoaded() {
    if (window.ZXing) return Promise.resolve();
    if (loading) return loading;
    loading = new Promise(function (resolve, reject) {
      var script = document.createElement('script');
      script.id = ZXING_SCRIPT_ID;
      script.src = ZXING_SRC;
      script.async = true;
      script.onload = function () {
        resolve();
      };
      script.onerror = function () {
        loading = null;
        script.remove();
        reject(new Error('Could not load the barcode library'));
      };
      document.head.appendChild(script);
    });
    return loading;
  }

  // Looks for a single code in an image (screenshot, photo).
  // Resolves with { format: 'QR_CODE' | 'AZTEC' | ..., text } or null.
  async function decodeImage(bytes, mimeType) {
    await ensureLoaded();
    var url = URL.createObjectURL(new Blob([bytes], { type: mimeType }));
    try {
      var hints = new Map();
      hints.set(ZXing.DecodeHintType.TRY_HARDER, true);
      var reader = new ZXing.BrowserMultiFormatReader(hints);
      var result = await reader.decodeFromImageUrl(url);
      return {
        format: ZXing.BarcodeFormat[result.getBarcodeFormat()],
        text: result.getText(),
      };
    } catch (_) {
      return null;
    } finally {
      URL.revokeObjectURL(url);
    }
  }

  window.planerzBarcode = { ensureLoaded: ensureLoaded, decodeImage: decodeImage };
})();
