/**
 * Firebase Functions – Produção
 * - callables v2: claimPurchase, deleteAccount (com App Check)
 * - trigger auth v1: createUserDoc (estável para deploy)
 */

// ✅ v2 (2nd gen)
const { setGlobalOptions } = require("firebase-functions/v2");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");

// ✅ v1 (1st gen) - IMPORT CORRETO (corrige o .auth.user() undefined)
const functionsV1 = require("firebase-functions/v1");

const admin = require("firebase-admin");
const { google } = require("googleapis");

// ================= INIT =================
if (admin.apps.length === 0) {
  admin.initializeApp();
}

// ✅ Região para v2
setGlobalOptions({
  region: "us-central1",
  maxInstances: 10,
});

// ================= CONFIG =================
const PACKAGE_NAME = "com.sonoramente.app";

// ✅ Whitelist de produtos Android (produção)
const ALLOWED_ANDROID_PRODUCTS = new Set(["pacote_premium"]);

// =====================================================
// ================== AUTH TRIGGER (v1) =================
// =====================================================
// ✅ Cria doc do usuário e seta claims iniciais
exports.createUserDoc = functionsV1
  .region("us-central1")
  .auth.user()
  .onCreate(async (user) => {
    const uid = user.uid;

    logger.info("👤 createUserDoc onCreate", {
      uid,
      email: user.email ?? null,
      providerData: (user.providerData || []).map((p) => p.providerId),
    });

    // 1) Claims iniciais (para regras funcionarem)
    try {
      await admin.auth().setCustomUserClaims(uid, {
        sessionValid: true,
        basePlan: "gratis",
        addons: [],
      });
      logger.info("✅ Claims iniciais setadas", { uid });
    } catch (e) {
      logger.error("❌ Falha ao setar claims iniciais", {
        uid,
        message: e?.message ?? String(e),
        stack: e?.stack ?? null,
      });
    }

    // 2) Firestore doc
    const userRef = admin.firestore().collection("users").doc(uid);

    await userRef.set(
      {
        uid,
        name: user.displayName ?? "",
        email: user.email ?? "",
        photoURL: user.photoURL ?? "",
        plan: "gratis", // compat legado
        basePlan: "gratis",
        addons: [],
        deviceIdAtivo: null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    logger.info("✅ Firestore user doc criado/mesclado", { uid });
  });

// =====================================================
// ================== CLAIM PURCHASE (v2) ===============
// =====================================================
exports.claimPurchase = onCall({ enforceAppCheck: true }, async (request) => {
  try {
    if (!request.app) {
      throw new HttpsError(
        "failed-precondition",
        "App Check inválido. Instale/atualize pela loja oficial e tente novamente."
      );
    }

    const { productId, purchaseToken, packageName } = request.data || {};
    const authCtx = request.auth;

    if (!authCtx?.uid) {
      throw new HttpsError("unauthenticated", "Usuário não autenticado.");
    }
    if (!productId || !purchaseToken) {
      throw new HttpsError("invalid-argument", "Dados incompletos.");
    }

    // ✅ Bloqueia productId inventado
    if (!ALLOWED_ANDROID_PRODUCTS.has(String(productId))) {
      logger.warn("❌ productId não permitido", {
        uid: authCtx.uid,
        productId,
      });
      throw new HttpsError("permission-denied", "Produto inválido.");
    }

    // ✅ Não confia no packageName do app
    if (packageName && packageName !== PACKAGE_NAME) {
      logger.warn("❌ packageName divergente", {
        uid: authCtx.uid,
        received: packageName,
        expected: PACKAGE_NAME,
      });
      throw new HttpsError("permission-denied", "packageName inválido.");
    }

    const uid = authCtx.uid;

    logger.info("🔍 Validando compra", {
      uid,
      productId,
      packageName: PACKAGE_NAME,
      tokenLen: String(purchaseToken).length,
    });

    const auth = new google.auth.GoogleAuth({
      scopes: ["https://www.googleapis.com/auth/androidpublisher"],
    });

    const androidPublisher = google.androidpublisher({
      version: "v3",
      auth,
    });

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
      throw new HttpsError("failed-precondition", "Compra não concluída.");
    }

    // ACK
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

    // ✅ SKU pacote_premium -> libera basePlan basico (seu modelo)
    await admin.auth().setCustomUserClaims(uid, {
      sessionValid: true,
      basePlan: "basico",
      addons: [],
    });

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
    if (error instanceof HttpsError) {
      logger.error("❌ claimPurchase HttpsError:", {
        code: error.code,
        message: error.message,
        details: error.details ?? null,
      });
      throw error;
    }

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
// ================== DELETE ACCOUNT (v2) ===============
// =====================================================
exports.deleteAccount = require("./delete_account").deleteAccount;