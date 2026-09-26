'use strict';

/**
 * seed_preview_demo_trip.js
 *
 * Crée un voyage de démonstration complet (planning, repas, courses,
 * dépenses, chambres, covoiturage, jeux, « À emporter », annonces, messages)
 * dans le projet Firebase de PREVIEW uniquement, pour visualiser toute l'UI.
 *
 * Le voyage est rattaché au compte --owner-email (créateur) ; les autres
 * voyageurs sont des participants « placeholder » (sans compte).
 * Les dates sont relatives au jour d'exécution : le voyage est toujours « en cours ».
 *
 * Usage :
 *   node seed_preview_demo_trip.js --key <service-account-preview.json> --owner-email <email> [--apply] [--force]
 *
 *   --apply   Écriture réelle (défaut : dry-run, rien n'est écrit)
 *   --force   Remplace le voyage de démo s'il existe déjà (même id)
 *
 * Garde-fou : refuse de s'exécuter si le projet n'est pas « planerz-preview ».
 */

const fs = require('fs');
const path = require('path');

function loadFirebaseAdmin() {
  try {
    return require('firebase-admin');
  } catch {
    return require(path.join(__dirname, 'migration', 'node_modules', 'firebase-admin'));
  }
}

const admin = loadFirebaseAdmin();

const TRIP_ID = 'demo-riviera';
const ALLOWED_PROJECT = 'planerz-preview';

function parseArgs(argv) {
  const opts = { keyPath: '', ownerEmail: '', apply: false, force: false };
  for (let i = 2; i < argv.length; i++) {
    const t = argv[i];
    if (t === '--apply') opts.apply = true;
    else if (t === '--force') opts.force = true;
    else if (t === '--key') opts.keyPath = (argv[++i] || '').trim();
    else if (t === '--owner-email') opts.ownerEmail = (argv[++i] || '').trim();
  }
  return opts;
}

function usage() {
  console.log(
    'Usage: node seed_preview_demo_trip.js --key <service-account-preview.json> ' +
      '--owner-email <email> [--apply] [--force]',
  );
  process.exit(1);
}

/** Local date helpers relative to today (run on the product owner's machine). */
function dayOffset(offset, hour = 0, minute = 0) {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth(), now.getDate() + offset, hour, minute);
}
function dateKey(offset) {
  const d = dayOffset(offset);
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${d.getFullYear()}-${mm}-${dd}`;
}

async function main() {
  const opts = parseArgs(process.argv);
  if (!opts.keyPath || !opts.ownerEmail) usage();

  const serviceAccount = JSON.parse(fs.readFileSync(path.resolve(opts.keyPath), 'utf8'));
  if (serviceAccount.project_id !== ALLOWED_PROJECT) {
    console.error(`Refus : projet « ${serviceAccount.project_id} » (seul ${ALLOWED_PROJECT} est autorisé).`);
    process.exit(1);
  }
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  const db = admin.firestore();
  const { Timestamp } = admin.firestore;
  const ts = (date) => Timestamp.fromDate(date);

  const owner = await admin.auth().getUserByEmail(opts.ownerEmail);
  const me = owner.uid;
  const userDoc = await db.collection('users').doc(me).get();
  const myName = userDoc.data()?.account?.name || owner.displayName || 'Moi';

  const tripRef = db.collection('trips').doc(TRIP_ID);
  const existing = await tripRef.get();
  if (existing.exists && !opts.force) {
    console.error(`Le voyage ${TRIP_ID} existe déjà. Relancer avec --force pour le remplacer.`);
    process.exit(1);
  }

  // --- Build every write first, then either print (dry-run) or commit. ---
  const writes = [];
  const set = (ref, data) => writes.push({ ref, data });

  const people = [
    { key: 'p_me', name: myName, userId: me },
    { key: 'p_leo', name: 'Léo' },
    { key: 'p_ines', name: 'Inès' },
    { key: 'p_hugo', name: 'Hugo' },
    { key: 'p_manon', name: 'Manon' },
    { key: 'p_yanis', name: 'Yanis', isChild: true },
  ];
  const everyone = people.map((p) => p.key);

  set(tripRef, {
    title: 'Démo Riviera — Biarritz',
    destination: 'Biarritz, France',
    address: '12 avenue de la Plage, 64200 Biarritz',
    linkUrl: '',
    description: 'Voyage de démonstration (données fictives).',
    photosStorageUrl: '',
    cupidonModeEnabled: false,
    carpoolModuleEnabled: true,
    roomsModuleEnabled: true,
    gamesModuleEnabled: true,
    ownerId: me,
    memberUserIds: [me],
    adminMemberIds: [],
    participantCount: people.length,
    inviteToken: 'demoriviera',
    startDate: ts(dayOffset(-1)),
    endDate: ts(dayOffset(3)),
    tripStartDayPart: 'evening',
    tripEndDayPart: 'morning',
    createdAt: Timestamp.now(),
  });

  for (const p of people) {
    set(tripRef.collection('participants').doc(p.key), {
      participantName: p.name,
      ...(p.userId ? { userId: p.userId, useProfileName: true } : {}),
      stayStartDateKey: dateKey(-1),
      stayStartDayPart: 'evening',
      stayEndDateKey: dateKey(3),
      stayEndDayPart: 'morning',
      cupidonEnabled: false,
      phoneVisibility: 'nobody',
      ...(p.isChild ? { isChild: true } : {}),
      createdAt: Timestamp.now(),
    });
  }

  set(tripRef.collection('expenseGroups').doc('commun'), {
    title: 'Commun',
    visibleToMemberIds: everyone,
    isDefault: true,
    createdAt: Timestamp.now(),
    createdBy: me,
  });

  // Activities (planned + suggestions)
  const activities = [
    ['Cours de surf à la Côte des Basques', 'sport', dayOffset(0, 10, 0), [me]],
    ['Balade au Rocher de la Vierge', 'hiking', dayOffset(0, 16, 30), []],
    ['Bodega La Cantine – pintxos', 'nightlife', dayOffset(0, 22, 0), []],
    ['Train Paris → Biarritz', 'transport', dayOffset(-1, 13, 12), []],
    ['Villa Itsasoa – check-in', 'accommodation', dayOffset(-1, 18, 0), []],
    ['Marché des Halles', 'market', dayOffset(1, 9, 30), [me]],
    ['Musée de la Mer', 'museum', dayOffset(1, 15, 0), []],
    ['Spa Thalasso', 'wellness', dayOffset(2, 11, 0), []],
    ['Retour en covoiturage', 'transport', dayOffset(3, 10, 0), []],
    ['Randonnée La Rhune', 'hiking', null, [me]],
    ['Soirée karaoké', 'karaoke', null, []],
    ['Escape game Anglet', 'games', null, [me]],
    ['Plage de la Milady', 'beach', null, []],
  ];
  activities.forEach(([label, category, plannedAt, votes], i) => {
    set(tripRef.collection('activities').doc(`a${i}`), {
      label, category, linkUrl: '', address: '', freeComments: '',
      ...(plannedAt ? { plannedAt: ts(plannedAt) } : {}),
      done: false, createdBy: me, votes, createdAt: Timestamp.now(),
    });
  });

  // Meals (cooked / restaurant / potluck)
  const ingredients = [
    { catalogItemId: '', label: 'Tomates', quantityValue: 6, quantityUnit: 'unit' },
    { catalogItemId: '', label: 'Oignons', quantityValue: 2, quantityUnit: 'unit' },
    { catalogItemId: '', label: 'Piment d’Espelette', quantityValue: 1, quantityUnit: 'unit' },
  ];
  const meals = [
    [-1, 'evening', '20:30', 'cooked', 'p_leo', [['plat', 'Axoa de veau'], ['dessert', 'Gâteau basque']]],
    [0, 'morning', '08:30', 'cooked', 'p_me', [['plat', 'Brunch pancakes']]],
    [0, 'midday', '13:00', 'restaurant', null, [], 'Le Surfing'],
    [0, 'evening', '20:00', 'potluck', null, []],
    [1, 'midday', '12:30', 'cooked', 'p_ines', [['entree', 'Salade de tomates'], ['plat', 'Piperade & jambon']]],
    [1, 'evening', '20:30', 'cooked', 'p_hugo', [['plat', 'Chipirons à la plancha']]],
  ];
  meals.forEach(([offset, part, time, mode, chef, comps, restaurantName], i) => {
    set(tripRef.collection('meals').doc(`m${i}`), {
      mealDateKey: dateKey(offset), mealDayPart: part, mealTimeHHMM: time,
      participantIds: part === 'morning' ? everyone.slice(0, 4) : everyone,
      chefParticipantId: chef,
      components: comps.map(([kind, title], idx) => ({
        id: `c${idx}`, kind, title, order: idx, ingredients,
        recipeInstructions: '', ingredientsGeneratedByAi: false, lockedBy: null,
      })),
      mealMode: mode, restaurantActivityId: '', restaurantName: restaurantName || '',
      potluckItems: mode === 'potluck'
        ? [
            { id: 'k1', label: 'Chips & olives', addedBy: 'p_leo', category: 'salty', quantityUnits: 2 },
            { id: 'k2', label: 'Tarte aux pommes', addedBy: 'p_manon', category: 'sweet', quantityUnits: 1 },
            { id: 'k3', label: 'Cidre basque', addedBy: 'p_hugo', category: 'alcohol', quantityUnits: 3 },
          ]
        : [],
      componentsUserOrdered: false, createdBy: me, createdAt: Timestamp.now(),
    });
  });

  // Shopping — manual list
  const shopping = [
    ['Baguettes', 3, 'unit', true, me], ['Lait demi-écrémé', 2, 'l', false, me],
    ['Œufs', 12, 'unit', false, null], ['Beurre doux', 250, 'g', true, me],
    ['Café moulu', 1, 'unit', false, null], ['Crème solaire SPF50', 1, 'unit', false, null],
    ['Tomates', 1.5, 'kg', false, null], ['Jambon de Bayonne', 300, 'g', false, me],
    ['Fromage de brebis', 1, 'unit', false, null], ['Eau pétillante', 6, 'unit', false, null],
  ];
  shopping.forEach(([label, q, unit, checked, claimedBy], i) => {
    set(tripRef.collection('shoppingItems').doc(`s${i}`), {
      label, checked, quantityValue: q, quantityUnit: unit, order: i,
      createdAt: Timestamp.now(), createdBy: me, ...(claimedBy ? { claimedBy } : {}),
    });
  });
  // Shopping — consolidated list
  const cons = tripRef.collection('consolidatedShoppingItems');
  set(cons.doc('meta'), {
    categories: [
      { id: '1', fr: 'Fruits & légumes', en: 'Fruits & vegetables' },
      { id: '2', fr: 'Crèmerie', en: 'Dairy' },
      { id: '3', fr: 'Boucherie & charcuterie', en: 'Meat' },
      { id: '4', fr: 'Épicerie', en: 'Grocery' },
    ],
    summary: {}, updatedAt: Timestamp.now(), updatedBy: me,
  });
  [
    ['Tomates', 18, 'unit', '1', true], ['Oignons', 6, 'unit', '1', false], ['Poivrons', 4, 'unit', '1', false],
    ['Beurre doux', 250, 'g', '2', false], ['Crème fraîche', 200, 'ml', '2', false],
    ['Épaule de veau', 1.2, 'kg', '3', false], ['Chipirons', 800, 'g', '3', false],
    ['Farine', 1, 'kg', '4', false],
  ].forEach(([label, q, unit, categoryId, checked], i) => {
    set(cons.doc(`c${i}`), {
      label, checked, quantityValue: q, quantityUnit: unit, order: i, categoryId,
      createdAt: Timestamp.now(), createdBy: me,
    });
  });

  // Expenses
  [
    ['Courses Carrefour', 142.6, 'p_me', 'shopping_cart', -1],
    ['Location villa', 1260, 'p_leo', 'villa', -1],
    ['Cours de surf', 210, 'p_ines', 'receipt_long', 0],
    ['Restaurant Le Surfing', 186.4, 'p_hugo', 'restaurant', 0],
    ['Essence', 64.2, 'p_leo', 'local_gas_station', -1],
  ].forEach(([title, amount, paidBy, icon, offset], i) => {
    set(tripRef.collection('expenses').doc(`e${i}`), {
      groupId: 'commun', operationType: 'expense', title, amount, currency: 'EUR',
      paidBy, participantIds: everyone, icon, expenseDate: ts(dayOffset(offset)),
      createdAt: Timestamp.now(), createdBy: me, splitMode: 'equal',
    });
  });

  // Rooms
  [
    ['Chambre océan', [{ type: 'double', kind: 'regular', assignedMemberIds: ['p_me', 'p_leo'] }]],
    ['Chambre jardin', [
      { type: 'single', kind: 'regular', assignedMemberIds: ['p_ines'] },
      { type: 'single', kind: 'regular', assignedMemberIds: ['p_manon'] },
    ]],
    ['Mezzanine', [
      { type: 'single', kind: 'regular', assignedMemberIds: ['p_hugo'] },
      { type: 'single', kind: 'extra', assignedMemberIds: [] },
    ]],
  ].forEach(([name, beds], i) => {
    set(tripRef.collection('rooms').doc(`r${i}`), {
      name, beds, assignedMemberIds: beds.flatMap((b) => b.assignedMemberIds),
      createdAt: Timestamp.now(), createdBy: me,
    });
  });

  // Carpool
  set(tripRef.collection('sections').doc('carpool'), {
    cars: [
      {
        id: 'car1', createdByUserId: me, driverParticipantId: 'p_leo',
        meetingPointAddress: 'Gare de Bayonne', nearestTransitStop: 'Bayonne',
        departureAt: ts(dayOffset(-1, 17, 30)), availableSeats: 4,
        assignedParticipantIds: ['p_me', 'p_ines'], goesShopping: true,
        createdAt: Timestamp.now(), updatedAt: Timestamp.now(),
      },
      {
        id: 'car2', createdByUserId: me, driverParticipantId: 'p_hugo',
        meetingPointAddress: 'Aéroport de Biarritz', nearestTransitStop: 'Biarritz Aéroport',
        departureAt: ts(dayOffset(-1, 19, 0)), availableSeats: 3,
        assignedParticipantIds: ['p_manon'], goesShopping: false,
        createdAt: Timestamp.now(), updatedAt: Timestamp.now(),
      },
    ],
  });

  // Board games
  ['Dixit', 'Codenames', 'Skyjo', 'Les Loups-Garous'].forEach((name, i) => {
    set(tripRef.collection('boardGames').doc(`g${i}`), {
      name, linkUrl: '', linkPreview: {}, createdBy: me,
      createdAt: Timestamp.now(), updatedAt: Timestamp.now(),
    });
  });

  // "À emporter" (owner's packing list)
  const packing = tripRef.collection('packingLists').doc('p_me');
  set(packing, { enabled: true, updatedAt: Timestamp.now() });
  [
    ['Maillot de bain', true, 'self', false], ['Combinaison de surf', false, 'self', false],
    ['Crème solaire', false, 'self', true], ['Enceinte bluetooth', false, 'self', true],
    ['Serviette de plage', true, 'self', false],
  ].forEach(([label, checked, scope, shared], i) => {
    set(packing.collection('items').doc(`k${i}`), { label, checked, scope, shared, createdAt: Timestamp.now() });
  });

  // Announcements & messages
  set(tripRef.collection('announcements').doc('an1'), {
    text: 'Rendez-vous à la villa à 18 h. Code du portail : 1964.', authorId: me, createdAt: ts(dayOffset(-2, 10, 0)),
  });
  set(tripRef.collection('messages').doc('msg0'), {
    authorId: me, text: 'Bienvenue dans le voyage de démo 🌊', type: 'text',
    threadType: 'main', visibilityType: 'trip_all', createdAt: ts(dayOffset(0, 9, 0)),
  });

  // --- Report / commit ---
  const byCollection = {};
  for (const w of writes) {
    const parts = w.ref.path.split('/');
    const coll = parts.length > 2 ? parts[parts.length - 2] : parts[0];
    byCollection[coll] = (byCollection[coll] || 0) + 1;
  }
  console.log(`Projet : ${serviceAccount.project_id}`);
  console.log(`Propriétaire : ${opts.ownerEmail} (${me})`);
  console.log(`Voyage : trips/${TRIP_ID}${existing.exists ? ' (existe déjà, sera remplacé)' : ''}`);
  console.table(byCollection);

  if (!opts.apply) {
    console.log('Dry-run : rien n’a été écrit. Relancer avec --apply pour écrire.');
    return;
  }
  if (existing.exists && opts.force) {
    await db.recursiveDelete(tripRef);
  }
  let batch = db.batch();
  let count = 0;
  for (const w of writes) {
    batch.set(w.ref, w.data);
    if (++count % 400 === 0) {
      await batch.commit();
      batch = db.batch();
    }
  }
  await batch.commit();
  console.log(`${writes.length} documents écrits. Voyage « Démo Riviera » prêt.`);
}

main().then(() => process.exit(0), (err) => {
  console.error(err);
  process.exit(1);
});
