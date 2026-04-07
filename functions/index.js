const admin = require('firebase-admin');
const { onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const cheerio = require('cheerio');

admin.initializeApp();

function normalizeString(v) {
  return (typeof v === 'string' ? v : '').trim();
}

function safeUrl(v) {
  const s = normalizeString(v);
  if (!s) return null;
  try {
    const u = new URL(s);
    if (u.protocol !== 'http:' && u.protocol !== 'https:') return null;
    return u;
  } catch {
    return null;
  }
}

function pickFirst(...values) {
  for (const v of values) {
    const s = normalizeString(v);
    if (s) return s;
  }
  return '';
}

async function fetchHtml(url) {
  const res = await fetch(url.toString(), {
    redirect: 'follow',
    headers: {
      'user-agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
      accept:
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    },
  });
  if (!res.ok) {
    throw new Error(`HTTP ${res.status}`);
  }
  return await res.text();
}

function parsePreviewFromHtml(pageUrl, html) {
  const $ = cheerio.load(html);

  const meta = (key) =>
    pickFirst(
      $(`meta[property="${key}"]`).attr('content'),
      $(`meta[name="${key}"]`).attr('content')
    );

  const ogTitle = meta('og:title');
  const ogDescription = meta('og:description');
  const ogImage = meta('og:image');
  const ogSiteName = meta('og:site_name');

  const twitterTitle = meta('twitter:title');
  const twitterDescription = meta('twitter:description');
  const twitterImage = meta('twitter:image');

  const titleTag = normalizeString($('title').first().text());

  const title = pickFirst(ogTitle, twitterTitle, titleTag);
  const description = pickFirst(ogDescription, twitterDescription);
  const siteName = pickFirst(ogSiteName, pageUrl.hostname);
  const imageRaw = pickFirst(ogImage, twitterImage);

  let imageUrl = '';
  if (imageRaw) {
    try {
      imageUrl = new URL(imageRaw, pageUrl).toString();
    } catch {
      imageUrl = '';
    }
  }

  return {
    title,
    description,
    siteName,
    imageUrl,
  };
}

exports.generateTripLinkPreview = onDocumentUpdated(
  {
    document: 'trips/{tripId}',
    region: 'europe-west1',
    timeoutSeconds: 30,
    memory: '256MiB',
  },
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};

    const beforeUrl = normalizeString(before.linkUrl);
    const afterUrl = normalizeString(after.linkUrl);

    // Avoid loops: only run when linkUrl actually changes.
    if (beforeUrl === afterUrl) return;

    const tripRef = event.data.after.ref;

    if (!afterUrl) {
      await tripRef.set(
        {
          linkPreview: admin.firestore.FieldValue.delete(),
        },
        { merge: true }
      );
      return;
    }

    const parsed = safeUrl(afterUrl);
    if (!parsed) {
      await tripRef.set(
        {
          linkPreview: {
            status: 'error',
            url: afterUrl,
            error: 'invalid_url',
            fetchedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        },
        { merge: true }
      );
      return;
    }

    // Mark as loading (UI can show spinner).
    await tripRef.set(
      {
        linkPreview: {
          status: 'loading',
          url: parsed.toString(),
          fetchedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      },
      { merge: true }
    );

    try {
      const html = await fetchHtml(parsed);
      const preview = parsePreviewFromHtml(parsed, html);

      const hasSomething =
        preview.title || preview.description || preview.imageUrl || preview.siteName;

      await tripRef.set(
        {
          linkPreview: {
            status: hasSomething ? 'ok' : 'empty',
            url: parsed.toString(),
            title: preview.title,
            description: preview.description,
            siteName: preview.siteName,
            imageUrl: preview.imageUrl,
            fetchedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        },
        { merge: true }
      );
    } catch (e) {
      await tripRef.set(
        {
          linkPreview: {
            status: 'error',
            url: parsed.toString(),
            error: String(e),
            fetchedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        },
        { merge: true }
      );
    }
  }
);

exports.joinTripWithInvite = onCall(
  {
    region: 'europe-west1',
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecte');
    }

    const tripId = normalizeString(request.data?.tripId);
    const token = normalizeString(request.data?.token);
    if (!tripId || !token) {
      throw new HttpsError('invalid-argument', 'Lien d invitation invalide');
    }

    const tripRef = admin.firestore().collection('trips').doc(tripId);
    await admin.firestore().runTransaction(async (tx) => {
      const snap = await tx.get(tripRef);
      if (!snap.exists) {
        throw new HttpsError('not-found', 'Voyage introuvable');
      }

      const data = snap.data() || {};
      const expectedToken = normalizeString(data.inviteToken);
      if (!expectedToken || expectedToken !== token) {
        throw new HttpsError(
          'permission-denied',
          'Lien d invitation invalide ou expire'
        );
      }

      const memberIds = Array.isArray(data.memberIds)
        ? data.memberIds.map((v) => String(v))
        : [];
      if (memberIds.includes(uid)) {
        return;
      }

      memberIds.push(uid);
      tx.update(tripRef, {
        memberIds,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    return { ok: true };
  }
);

