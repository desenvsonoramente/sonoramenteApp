/**
 * Firebase Functions v2 – claimPurchase (PRODUÇÃO)
 * Google Play Billing Validation
 */

const { setGlobalOptions } = require("firebase-functions");
const { onCall } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const { google } = require("googleapis");

// ================= INIT =================
// ✅ Inicializa APENAS UMA VEZ
if (admin.apps.length === 0) {
  admin.initializeApp();
}
setGlobalOptions({ maxInstances: 10 });

// ================= FUNCTION =================
exports.claimPurchase = onCall(async (request) => {
  try {
    const { productId, purchaseToken, packageName } = request.data;
    const context = request.auth;

    if (!context?.uid) {
      throw new Error("Usuário não autenticado.");
    }

    if (!productId || !purchaseToken || !packageName) {
      throw new Error("Dados incompletos.");
    }

    const uid = context.uid;

    logger.info("🔍 Validando compra", {
      uid,
      productId,
      packageName,
    });

    // ================= GOOGLE PLAY CLIENT (LAZY) =================
    const auth = new google.auth.GoogleAuth({
      scopes: ["https://www.googleapis.com/auth/androidpublisher"],
    });

    const androidPublisher = google.androidpublisher({
      version: "v3",
      auth,
    });

    // ================= VALIDAR COMPRA =================
    const purchase = await androidPublisher.purchases.products.get({
      packageName,
      productId,
      token: purchaseToken,
    });

    const data = purchase.data;

    if (data.purchaseState !== 0) {
      throw new Error("Compra não concluída.");
    }

    // ================= ACKNOWLEDGE =================
    if (data.acknowledgementState === 0) {
      await androidPublisher.purchases.products.acknowledge({
        packageName,
        productId,
        token: purchaseToken,
      });

      logger.info("✅ Compra acknowledged");
    }

    // ================= FIRESTORE =================
    await admin.firestore().collection("users").doc(uid).set(
      {
        plan: "basico",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastPurchase: {
          productId,
          platform: "android",
          purchasedAt: admin.firestore.Timestamp.fromMillis(
            Number(data.purchaseTimeMillis)
          ),
        },
      },
      { merge: true }
    );

    logger.info("🎉 Plano básico liberado", { uid });

    return { success: true };
  } catch (error) {
    logger.error("❌ claimPurchase erro:", error);
    throw new Error(error.message);
  }
});

// =====================================================
// ================== DELETE ACCOUNT ====================
// =====================================================

// ✅ Exporta do arquivo, sem reinicializar admin lá dentro
exports.deleteAccount = require("./delete_account").deleteAccount;
