/**
 * Firebase Functions v2 – claimPurchase (PRODUÇÃO)
 * Google Play Billing Validation
 */

const { setGlobalOptions } = require("firebase-functions");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const { google } = require("googleapis");

// ================= INIT =================
// ✅ Inicializa APENAS UMA VEZ
if (admin.apps.length === 0) {
  admin.initializeApp();
}
setGlobalOptions({ maxInstances: 10 });

// ================= CONFIG =================
// ✅ Não confie no packageName que vem do app.
// Ajuste para o packageName real do seu Android:
const PACKAGE_NAME = "com.sonoramente.app";

// ================= FUNCTION =================
exports.claimPurchase = onCall(async (request) => {
  try {
    const { productId, purchaseToken, packageName } = request.data;
    const context = request.auth;

    if (!context?.uid) {
      throw new HttpsError("unauthenticated", "Usuário não autenticado.");
    }

    if (!productId || !purchaseToken) {
      throw new HttpsError("invalid-argument", "Dados incompletos.");
    }

    // ✅ Valida packageName vindo do app (se vier diferente, bloqueia).
    // Se você quiser parar de mandar packageName do app, pode:
    // - remover do app
    // - e aqui usar só PACKAGE_NAME.
    if (packageName && packageName !== PACKAGE_NAME) {
      logger.warn("❌ packageName divergente", {
        uid: context.uid,
        received: packageName,
        expected: PACKAGE_NAME,
      });
      throw new HttpsError("permission-denied", "packageName inválido.");
    }

    const uid = context.uid;

    logger.info("🔍 Validando compra", {
      uid,
      productId,
      packageName: PACKAGE_NAME,
      tokenLen: String(purchaseToken).length,
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
      packageName: PACKAGE_NAME,
      productId,
      token: purchaseToken,
    });

    const data = purchase.data;

    logger.info("📦 Resposta Play", {
      uid,
      productId,
      orderId: data.orderId ?? null,
      purchaseState: data.purchaseState,
      acknowledgementState: data.acknowledgementState,
      purchaseTimeMillis: data.purchaseTimeMillis ?? null,
      consumptionState: data.consumptionState ?? null,
    });

    if (data.purchaseState !== 0) {
      // 0 = purchased (em compras INAPP)
      throw new HttpsError("failed-precondition", "Compra não concluída.");
    }

    // ================= ACKNOWLEDGE =================
    if (data.acknowledgementState === 0) {
      await androidPublisher.purchases.products.acknowledge({
        packageName: PACKAGE_NAME,
        productId,
        token: purchaseToken,
      });

      logger.info("✅ Compra acknowledged", { uid, productId });
    } else {
      logger.info("ℹ️ Compra já estava acknowledged", { uid, productId });
    }

    // ================= FIRESTORE =================
    // ✅ Mantém "plan" pra não quebrar nada
    // ✅ Adiciona "basePlan" porque seu app lê basePlan
    await admin.firestore().collection("users").doc(uid).set(
      {
        plan: "basico",
        basePlan: "basico",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastPurchase: {
          productId,
          platform: "android",
          orderId: data.orderId ?? null,
          purchasedAt: admin.firestore.Timestamp.fromMillis(
            Number(data.purchaseTimeMillis)
          ),
        },
      },
      { merge: true }
    );

    logger.info("🎉 Plano básico liberado", { uid, productId });

    return {
      success: true,
      orderId: data.orderId ?? null,
    };
  } catch (error) {
    // Se já for HttpsError, repassa
    if (error instanceof HttpsError) {
      logger.error("❌ claimPurchase HttpsError:", {
        code: error.code,
        message: error.message,
        details: error.details ?? null,
      });
      throw error;
    }

    // Erro genérico (Google API, permissão, etc.)
    logger.error("❌ claimPurchase erro:", {
      message: error?.message ?? String(error),
      stack: error?.stack ?? null,
    });

    throw new HttpsError(
      "internal",
      error?.message ?? "Erro interno ao validar compra."
    );
  }
});

// =====================================================
// ================== DELETE ACCOUNT ====================
// =====================================================

// ✅ Exporta do arquivo, sem reinicializar admin lá dentro
exports.deleteAccount = require("./delete_account").deleteAccount;
