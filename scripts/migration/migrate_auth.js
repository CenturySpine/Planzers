const admin = require('firebase-admin');
const fs = require('fs');

async function migrateAuth() {
    try {
        console.log("Lecture des clés...");
        const sourceKey = JSON.parse(fs.readFileSync('./source-key.json', 'utf8'));
        const destKey = JSON.parse(fs.readFileSync('./dest-key.json', 'utf8'));

        const sourceApp = admin.initializeApp({
            credential: admin.credential.cert(sourceKey)
        }, 'source');

        const destApp = admin.initializeApp({
            credential: admin.credential.cert(destKey)
        }, 'dest');

        const sourceAuth = sourceApp.auth();
        const destAuth = destApp.auth();

        console.log("--- MIGRATION DES UTILISATEURS (AUTH) ---");
        
        let usersToMigrate = [];
        let nextPageToken;
        
        // 1. Récupérer tous les utilisateurs de l'ancienne base
        do {
            const listUsersResult = await sourceAuth.listUsers(1000, nextPageToken);
            usersToMigrate = usersToMigrate.concat(listUsersResult.users);
            nextPageToken = listUsersResult.pageToken;
        } while (nextPageToken);

        console.log(`Trouvé ${usersToMigrate.length} utilisateurs à migrer.`);

        if (usersToMigrate.length === 0) {
            console.log("Aucun utilisateur à migrer.");
            process.exit(0);
        }

        // 2. Formater les données pour l'import
        const userImportRecords = usersToMigrate.map(user => {
            const record = {
                uid: user.uid,
                email: user.email,
                emailVerified: user.emailVerified,
                displayName: user.displayName,
                photoURL: user.photoURL,
                disabled: user.disabled,
                metadata: {
                    creationTime: user.metadata.creationTime,
                    lastSignInTime: user.metadata.lastSignInTime,
                },
                providerData: user.providerData.map(p => ({
                    uid: p.uid,
                    displayName: p.displayName,
                    email: p.email,
                    photoURL: p.photoURL,
                    providerId: p.providerId,
                }))
            };
            
            // Retirer les champs undefined pour éviter les erreurs de l'API
            Object.keys(record).forEach(key => record[key] === undefined && delete record[key]);
            if (record.metadata) {
                Object.keys(record.metadata).forEach(key => record.metadata[key] === undefined && delete record.metadata[key]);
            }
            return record;
        });

        // 3. Importer les utilisateurs dans la nouvelle base par lot de 1000 (limite Firebase)
        for (let i = 0; i < userImportRecords.length; i += 1000) {
            const batch = userImportRecords.slice(i, i + 1000);
            console.log(`Importation du lot de ${batch.length} utilisateurs...`);
            
            const result = await destAuth.importUsers(batch, {
                hash: { algorithm: 'STANDARD_SCRYPT' } // Algorithme par défaut obligatoire même sans mot de passe
            });
            
            console.log(`✔ Succès: ${result.successCount}`);
            if (result.failureCount > 0) {
                console.log(`❌ Échecs: ${result.failureCount}`);
                result.errors.forEach(err => {
                    console.log(`  Erreur à l'index ${err.index}: ${err.error.message}`);
                });
            }
        }

        console.log("\n🎉 MIGRATION AUTH TERMINÉE !");
        
        
        process.exit(0);
    } catch (error) {
        console.error("Erreur générale :", error);
        process.exit(1);
    }
}

migrateAuth();
