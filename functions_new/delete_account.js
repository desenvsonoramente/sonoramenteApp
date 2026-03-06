/**
 * Firebase Functions v2 – deleteAccount (PRODUÇÃO)
 * - Exige App Check (bloqueia clones)
 * - Apaga Firestore (doc + subcollections) e Auth do usuário
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

// ✅ NÃO inicializa aqui. Quem inicializa é o index.js

const REGION = "us-central1";

exports.deleteAccount = onCall(
  { region: REGION, enforceAppCheck: true },
  async (request) => {
    try {
      // App Check (mensagem mais clara)
      if (!request.app) {
        throw new HttpsError(
          "failed-precondition",
          "App Check inválido. Instale o app pela loja oficial e tente novamente."
        );
      }

      if (!request.auth?.uid) {
        throw new HttpsError("unauthenticated", "Usuário não autenticado.");
      }

      const uid = request.auth.uid;
      logger.info("🧠 DELETE_ACCOUNT -> UID", { uid });

      // ================= FIRESTORE =================
      const userRef = admin.firestore().collection("users").doc(uid);

      // ✅ Apaga doc + subcoleções de forma robusta
      await admin.firestore().recursiveDelete(userRef);

      logger.info("🗑️ Firestore user doc + subcollections deleted", { uid });

      // ================= AUTH =================
      await admin.auth().deleteUser(uid);
      logger.info("✅ FirebaseAuth user deleted", { uid });

      return { success: true };
    } catch (error) {
      if (error instanceof HttpsError) {
        logger.error("❌ DELETE_ACCOUNT HttpsError", {
          code: error.code,
          message: error.message,
          details: error.details ?? null,
        });
        throw error;
      }

      logger.error("❌ DELETE_ACCOUNT ERROR", {
        message: error?.message ?? String(error),
        stack: error?.stack ?? null,
      });

      throw new HttpsError(
        "internal",
        error?.message ?? "Erro interno ao deletar conta."
      );
    }
  }
);