// Thin Planerz-specific wrapper around the shared OAuth provider core
// (functions/vendor/oauth-provider-core, a git submodule — see its README
// for the reusable contract). The only Planerz-specific piece is admin
// gating (isApplicationOwner) and the exported callable names, which must
// stay stable since the Flutter app already calls them by these names.

const admin = require('firebase-admin');
const { HttpsError } = require('firebase-functions/v2/https');
const { model, createClientAdmin } = require('./vendor/oauth-provider-core');

async function requireApplicationOwner(uid) {
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Utilisateur non connecté');
  }
  const snap = await admin.firestore().collection('users').doc(uid).get();
  const userData = snap.exists ? snap.data() || {} : {};
  if (userData.isApplicationOwner !== true) {
    throw new HttpsError('permission-denied', 'Accès réservé aux administrateurs');
  }
}

const {
  getClientPublicInfo,
  authorizeClient,
  revokeConnectedApp,
  createClient,
  listClients,
  deleteClient,
} = createClientAdmin({ model, requireAdmin: requireApplicationOwner });

exports.getOAuthClientPublicInfo = getClientPublicInfo;
exports.authorizeOAuthClient = authorizeClient;
exports.revokeConnectedApp = revokeConnectedApp;
exports.createOAuthClient = createClient;
exports.listOAuthClients = listClients;
exports.deleteOAuthClient = deleteClient;
