/**
 * Firebase Functions v2 – deleteAccount (PRODUÇÃO)
 * Apaga Firestore, subcollections e Auth do usuário
 */

const { onCall } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

// ✅ NÃO inicializa aqui. Quem inicializa é o index.js

exports.deleteAccount = onCall(async (request) => {
  try {
    const context = request.auth;

    if (!context?.uid) {
      throw new Error("Usuário não autenticado.");
    }

    const uid = context.uid;
    logger.info("🧠 DELETE_ACCOUNT -> UID:", uid);

    // ================= FIRESTORE =================
    const userRef = admin.firestore().collection("users").doc(uid);

    async function deleteSubcollections(docRef) {
      const subcollections = await docRef.listCollections();
      for (const subcol of subcollections) {
        const snapshot = await subcol.get();
        for (const doc of snapshot.docs) {
          await deleteSubcollections(doc.ref);
          await doc.ref.delete();
          logger.info(`🗑️ Deleted subdoc ${doc.id} in ${subcol.id}`);
        }
      }
    }

    await deleteSubcollections(userRef);
    await userRef.delete();
    logger.info("🗑️ Firestore user doc deleted");

    // ================= AUTH =================
    await admin.auth().deleteUser(uid);
    logger.info("✅ FirebaseAuth user deleted");

    return { success: true };
  } catch (error) {
    logger.error("❌ DELETE_ACCOUNT ERROR:", error);
    throw new Error(error.message);
  }
});
