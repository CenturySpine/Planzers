const admin = require('firebase-admin');
const fs = require('fs');

async function migrate() {
    try {
        console.log("Lecture des clés...");
        const sourceKey = JSON.parse(fs.readFileSync('./source-key.json', 'utf8'));
        const destKey = JSON.parse(fs.readFileSync('./dest-key.json', 'utf8'));

        const sourceApp = admin.initializeApp({
            credential: admin.credential.cert(sourceKey),
            storageBucket: sourceKey.project_id + '.appspot.com'
        }, 'source');

        const destApp = admin.initializeApp({
            credential: admin.credential.cert(destKey),
            // Utilisation du domaine de bucket par défaut
            storageBucket: destKey.project_id + '.firebasestorage.app'
        }, 'dest');

        const sourceDb = sourceApp.firestore();
        const destDb = destApp.firestore();

        console.log("--- MIGRATION FIRESTORE ---");
        const collections = await sourceDb.listCollections();
        
        for (const collection of collections) {
            console.log(`Exportation de la collection: ${collection.id}...`);
            const snapshot = await collection.get();
            let count = 0;
            
            // Batch writes for performance
            let batch = destDb.batch();
            let batchCount = 0;
            
            for (const doc of snapshot.docs) {
                const destRef = destDb.collection(collection.id).doc(doc.id);
                batch.set(destRef, doc.data());
                count++;
                batchCount++;
                
                if (batchCount === 500) {
                    await batch.commit();
                    batch = destDb.batch();
                    batchCount = 0;
                }
            }
            if (batchCount > 0) {
                await batch.commit();
            }
            console.log(`✔ ${count} documents copiés dans ${collection.id}.`);
        }

        console.log("\n--- MIGRATION STORAGE ---");
        // On essaie avec les URLs par défaut, si l'utilisateur a des buckets custom, il faudra ajuster
        const sourceBucket = sourceApp.storage().bucket();
        // Le nouveau bucket créé par l'utilisateur
        const destBucket = destApp.storage().bucket(destKey.project_id + '.firebasestorage.app');

        console.log("Récupération de la liste des fichiers source...");
        try {
            const [files] = await sourceBucket.getFiles();
            console.log(`${files.length} fichiers trouvés.`);
            
            for (const file of files) {
                console.log(`Copie de ${file.name}...`);
                const destFile = destBucket.file(file.name);
                
                // Pipeline de stream: Source -> Dest
                await new Promise((resolve, reject) => {
                    file.createReadStream()
                        .on('error', reject)
                        .pipe(destFile.createWriteStream({
                            metadata: { contentType: file.metadata.contentType }
                        }))
                        .on('error', reject)
                        .on('finish', resolve);
                });
            }
            console.log("✔ Tous les fichiers ont été copiés.");
        } catch (e) {
            console.log("Erreur lors de la migration Storage (le bucket source est peut-être différent) :", e.message);
            console.log("On essaie avec l'autre format de bucket source (.firebasestorage.app)...");
            try {
                const altSourceBucket = sourceApp.storage().bucket(sourceKey.project_id + '.firebasestorage.app');
                const [files] = await altSourceBucket.getFiles();
                for (const file of files) {
                    console.log(`Copie de ${file.name}...`);
                    const destFile = destBucket.file(file.name);
                    await new Promise((resolve, reject) => {
                        file.createReadStream()
                            .pipe(destFile.createWriteStream({ metadata: { contentType: file.metadata.contentType } }))
                            .on('finish', resolve).on('error', reject);
                    });
                }
                console.log("✔ Tous les fichiers ont été copiés.");
            } catch (e2) {
                console.error("Échec de la migration Storage. Ignorez si vous n'aviez pas de fichiers.", e2.message);
            }
        }

        console.log("\n🎉 MIGRATION TERMINÉE AVEC SUCCÈS !");
        process.exit(0);
    } catch (error) {
        console.error("Erreur générale :", error);
        process.exit(1);
    }
}

migrate();
