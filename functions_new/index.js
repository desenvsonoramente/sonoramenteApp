/**
 * Firebase Functions – Produção
 * - callables v2: getUserProfile, claimPurchase, setActiveDevice, deleteAccount
 * - trigger auth v1: createUserDoc
 */

const { setGlobalOptions } = require("firebase-functions/v2");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");

const functionsV1 = require("firebase-functions/v1");
const admin = require("firebase-admin");
const { google } = require("googleapis");

// ================= INIT =================
if (admin.apps.length === 0) {
  admin.initializeApp();
}

// ================= CONFIG =================
const REGION = "us-central1";
const PACKAGE_NAME = "com.sonoramente.app";

// ✅ Service Account correta para Play API (FIXA)
const PLAY_SA =
  "google-play-validation@sonoramente-a7432.iam.gserviceaccount.com";

// ✅ Produção
const ENFORCE_APP_CHECK = true;

// ✅ Whitelist de produtos Android (produção)
const ALLOWED_ANDROID_PRODUCTS = new Set(["pacote_premium"]);

// ✅ Região para v2 + “prende” a service account no runtime
setGlobalOptions({
  region: REGION,
  maxInstances: 10,
  serviceAccount: PLAY_SA,
});

// =====================================================
// ================== HELPERS ===========================
// =====================================================
function safeStr(v, max = 200) {
  try {
    const s = String(v ?? "");
    return s.length > max ? s.slice(0, max) + "…" : s;
  } catch (_) {
    return "";
  }
}

function maskToken(token) {
  const t = String(token ?? "");
  if (!t) return "";
  if (t.length <= 10) return "***";
  return `***${t.slice(-6)}(len:${t.length})`;
}

function nowIso() {
  return new Date().toISOString();
}

function getRuntimeProjectId() {
  return (
    admin.app()?.options?.projectId ||
    process.env.GCLOUD_PROJECT ||
    process.env.GCP_PROJECT ||
    null
  );
}

function getRuntimeIdentitySnapshot() {
  const pick = (v) => (v == null ? null : String(v));

  return {
    kService: pick(process.env.K_SERVICE),
    kRevision: pick(process.env.K_REVISION),
    kConfiguration: pick(process.env.K_CONFIGURATION),
    functionTarget: pick(process.env.FUNCTION_TARGET),
    firebaseConfig: safeStr(process.env.FIREBASE_CONFIG, 300),
    gcloudProject: pick(process.env.GCLOUD_PROJECT),
    gcpProject: pick(process.env.GCP_PROJECT),
    adminProjectId: pick(admin.app()?.options?.projectId),
    configuredServiceAccount: PLAY_SA,
  };
}

function logRequestContext(name, request) {
  const headers = request?.rawRequest?.headers || {};
  const hasAuthHeader = !!headers.authorization;
  const hasAppCheckHeader =
    !!headers["x-firebase-appcheck"] || !!headers["X-Firebase-AppCheck"];

  const authHeader = String(headers.authorization || "");
  const authHeaderPrefix = authHeader ? authHeader.slice(0, 24) : "";

  logger.info(`🔎 ${name} context`, {
    ts: nowIso(),
    region: REGION,
    runtimeProjectId: getRuntimeProjectId(),
    runtimeIdentity: getRuntimeIdentitySnapshot(),

    hasAuthHeader,
    authHeaderPrefix,

    enforceAppCheck: ENFORCE_APP_CHECK,
    hasRequestApp: !!request.app,
    appId: request.app?.appId ?? null,
    appToken: request.app?.token ? "present" : "absent",
    hasAppCheckHeader,

    hasAuth: !!request.auth,
    uid: request.auth?.uid ?? null,
    authToken: request.auth?.token ? "present" : "absent",
  });
}

// =====================================================
// ================== AUTH TRIGGER (v1) =================
// =====================================================
exports.createUserDoc = functionsV1
  .region(REGION)
  .auth.user()
  .onCreate(async (user) => {
    const uid = user.uid;

    logger.info("👤 createUserDoc onCreate", {
      uid,
      email: user.email ?? null,
      providerData: (user.providerData || []).map((p) => p.providerId),
      runtimeProjectId: getRuntimeProjectId(),
      ts: nowIso(),
    });

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

    const userRef = admin.firestore().collection("users").doc(uid);

    try {
      const existingSnap = await userRef.get();
      const existingData = existingSnap.exists ? existingSnap.data() || {} : {};

      const existingBasePlan =
        typeof existingData.basePlan === "string" && existingData.basePlan.trim()
          ? existingData.basePlan
          : "gratis";

      const existingAddons = Array.isArray(existingData.addons)
        ? existingData.addons
        : [];

      const existingDeviceIdAtivo =
        typeof existingData.deviceIdAtivo === "string"
          ? existingData.deviceIdAtivo
          : "";

      await userRef.set(
        {
          uid,
          name:
            typeof existingData.name === "string" && existingData.name.trim()
              ? existingData.name
              : user.displayName ?? "",
          email:
            typeof existingData.email === "string" && existingData.email.trim()
              ? existingData.email
              : user.email ?? "",
          photoURL:
            typeof existingData.photoURL === "string"
              ? existingData.photoURL
              : user.photoURL ?? "",
          basePlan: existingBasePlan,
          addons: existingAddons,

          // ✅ preserva sessão já gravada
          deviceIdAtivo: existingDeviceIdAtivo,

          // ✅ preserva createdAt se já existir
          createdAt:
            existingData.createdAt ?? admin.firestore.FieldValue.serverTimestamp(),

          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      logger.info("✅ Firestore user doc criado/mesclado sem sobrescrever sessão", {
        uid,
        preservedDeviceIdAtivo: !!existingDeviceIdAtivo,
      });
    } catch (e) {
      logger.error("❌ Falha ao criar/mesclar user doc", {
        uid,
        message: e?.message ?? String(e),
        stack: e?.stack ?? null,
      });
      throw e;
    }
  });

// =====================================================
// ================== GET USER PROFILE (v2) =============
// =====================================================
exports.getUserProfile = onCall(
  {
    region: REGION,
    enforceAppCheck: ENFORCE_APP_CHECK,
    serviceAccount: PLAY_SA,
  },
  async (request) => {
    logRequestContext("getUserProfile", request);

    try {
      if (ENFORCE_APP_CHECK && !request.app) {
        throw new HttpsError(
          "failed-precondition",
          "App Check inválido. Instale/atualize pela Play Store e tente novamente."
        );
      }

      if (!request.auth?.uid) {
        throw new HttpsError("unauthenticated", "Usuário não autenticado.");
      }

      const uid = request.auth.uid;
      const ref = admin.firestore().collection("users").doc(uid);
      const snap = await ref.get();

      if (!snap.exists) {
        logger.info("ℹ️ getUserProfile | doc ausente", { uid });
        return {};
      }

      const data = snap.data() || {};

      logger.info("✅ getUserProfile ok", {
        uid,
        hasDeviceIdAtivo:
          typeof data.deviceIdAtivo === "string" && data.deviceIdAtivo.trim() !== "",
        basePlan: typeof data.basePlan === "string" ? data.basePlan : null,
        addonsCount: Array.isArray(data.addons) ? data.addons.length : 0,
        ts: nowIso(),
      });

      return {
        uid: data.uid ?? uid,
        name: typeof data.name === "string" ? data.name : "",
        email: typeof data.email === "string" ? data.email : "",
        photoURL: typeof data.photoURL === "string" ? data.photoURL : "",
        basePlan: typeof data.basePlan === "string" ? data.basePlan : "gratis",
        addons: Array.isArray(data.addons) ? data.addons : [],
        deviceIdAtivo:
          typeof data.deviceIdAtivo === "string" ? data.deviceIdAtivo : "",
        lastPurchase: data.lastPurchase ?? null,
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        logger.error("❌ getUserProfile HttpsError", {
          code: error.code,
          message: error.message,
          details: error.details ?? null,
          ts: nowIso(),
          runtimeProjectId: getRuntimeProjectId(),
        });
        throw error;
      }

      logger.error("❌ getUserProfile erro não tratado", {
        message: error?.message ?? String(error),
        stack: error?.stack ?? null,
        ts: nowIso(),
        runtimeProjectId: getRuntimeProjectId(),
      });

      throw new HttpsError("internal", "Erro interno ao obter perfil do usuário.");
    }
  }
);

// =====================================================
// ================== SET ACTIVE DEVICE (v2) ============
// =====================================================
exports.setActiveDevice = onCall(
  {
    region: REGION,
    enforceAppCheck: ENFORCE_APP_CHECK,
    serviceAccount: PLAY_SA,
  },
  async (request) => {
    logRequestContext("setActiveDevice", request);

    try {
      if (ENFORCE_APP_CHECK && !request.app) {
        throw new HttpsError(
          "failed-precondition",
          "App Check inválido. Instale/atualize pela Play Store e tente novamente."
        );
      }

      if (!request.auth?.uid) {
        throw new HttpsError("unauthenticated", "Usuário não autenticado.");
      }

      const uid = request.auth.uid;
      const deviceId = String(request.data?.deviceId ?? "").trim();

      if (!deviceId) {
        throw new HttpsError("invalid-argument", "deviceId é obrigatório.");
      }

      if (deviceId.length > 200) {
        throw new HttpsError("invalid-argument", "deviceId inválido.");
      }

      const ref = admin.firestore().collection("users").doc(uid);

      await ref.set(
        {
          deviceIdAtivo: deviceId,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      logger.info("✅ deviceIdAtivo atualizado no backend", {
        uid,
        deviceId: safeStr(deviceId, 80),
        ts: nowIso(),
      });

      return { success: true };
    } catch (error) {
      if (error instanceof HttpsError) {
        logger.error("❌ setActiveDevice HttpsError", {
          code: error.code,
          message: error.message,
          details: error.details ?? null,
          ts: nowIso(),
          runtimeProjectId: getRuntimeProjectId(),
        });
        throw error;
      }

      logger.error("❌ setActiveDevice erro não tratado", {
        message: error?.message ?? String(error),
        stack: error?.stack ?? null,
        ts: nowIso(),
        runtimeProjectId: getRuntimeProjectId(),
      });

      throw new HttpsError(
        "internal",
        "Erro interno ao atualizar dispositivo ativo."
      );
    }
  }
);

// =====================================================
// ================== CLAIM PURCHASE (v2) ===============
// =====================================================
exports.claimPurchase = onCall(
  {
    region: REGION,
    enforceAppCheck: ENFORCE_APP_CHECK,
    serviceAccount: PLAY_SA,
  },
  async (request) => {
    logRequestContext("claimPurchase", request);

    try {
      const rr = request?.rawRequest || null;
      const h = rr?.headers || {};
      const pickHeader = (k) => (h && h[k] != null ? "present" : "absent");

      logger.info("🧾 claimPurchase rawRequest snapshot", {
        ts: nowIso(),
        region: REGION,
        runtimeProjectId: getRuntimeProjectId(),
        hasRawRequest: !!rr,
        method: rr?.method ?? null,
        path: rr?.path ?? rr?.url ?? null,
        host: rr?.headers?.host ?? null,

        headers: {
          authorization: pickHeader("authorization"),
          xFirebaseAppCheckLower: pickHeader("x-firebase-appcheck"),
          xFirebaseAppCheckUpper: pickHeader("X-Firebase-AppCheck"),
          xForwardedFor: pickHeader("x-forwarded-for"),
          userAgent: pickHeader("user-agent"),
          origin: pickHeader("origin"),
          referer: pickHeader("referer"),
        },
      });
    } catch (e) {
      logger.warn("⚠️ rawRequest snapshot failed", {
        ts: nowIso(),
        message: e?.message ?? String(e),
      });
    }

    try {
      if (ENFORCE_APP_CHECK && !request.app) {
        throw new HttpsError(
          "failed-precondition",
          "App Check inválido. Instale/atualize pela Play Store e tente novamente."
        );
      }

      try {
        const headers = request?.rawRequest?.headers || {};
        const hasAuthHeader = !!headers.authorization;
        const hasAppCheckHeader =
          !!headers["x-firebase-appcheck"] || !!headers["X-Firebase-AppCheck"];

        logger.info("🧷 claimPurchase pre-auth snapshot", {
          ts: nowIso(),
          region: REGION,
          runtimeProjectId: getRuntimeProjectId(),
          enforceAppCheck: ENFORCE_APP_CHECK,

          hasAuthHeader,
          hasAppCheckHeader,

          hasAuth: !!request.auth,
          uid: request.auth?.uid ?? null,
          hasRequestApp: !!request.app,
          appId: request.app?.appId ?? null,
        });
      } catch (e) {
        logger.warn("⚠️ pre-auth snapshot failed", {
          ts: nowIso(),
          message: e?.message ?? String(e),
        });
      }

      if (!request.auth?.uid) {
        throw new HttpsError(
          "unauthenticated",
          "Usuário não autenticado (request.auth ausente). Verifique se o app está no MESMO projeto Firebase da Function e se o usuário está logado antes do call."
        );
      }

      const uid = request.auth.uid;
      const { productId, purchaseToken, packageName } = request.data || {};

      if (!productId || !purchaseToken) {
        throw new HttpsError("invalid-argument", "Dados incompletos.");
      }

      const pid = String(productId);

      if (!ALLOWED_ANDROID_PRODUCTS.has(pid)) {
        logger.warn("❌ productId não permitido", { uid, productId: pid });
        throw new HttpsError("permission-denied", "Produto inválido.");
      }

      if (packageName && packageName !== PACKAGE_NAME) {
        logger.warn("❌ packageName divergente", {
          uid,
          received: safeStr(packageName, 200),
          expected: PACKAGE_NAME,
        });
        throw new HttpsError("permission-denied", "packageName inválido.");
      }

      logger.info("🔍 Validando compra", {
        uid,
        productId: pid,
        packageName: PACKAGE_NAME,
        purchaseToken: maskToken(purchaseToken),
        runtimeProjectId: getRuntimeProjectId(),
        ts: nowIso(),
      });

      const auth = new google.auth.GoogleAuth({
        scopes: ["https://www.googleapis.com/auth/androidpublisher"],
      });

      const authClient = await auth.getClient();

      const androidPublisher = google.androidpublisher({
        version: "v3",
        auth: authClient,
      });

      try {
        const clientType = authClient?.constructor?.name ?? null;
        const creds = await auth.getCredentials();

        const at = await authClient.getAccessToken();
        const tokenPresent = typeof at === "string" ? !!at : !!at?.token;

        logger.info("🪪 GoogleAuth credentials snapshot", {
          ts: nowIso(),
          uid,
          runtimeProjectId: getRuntimeProjectId(),
          clientType,
          clientEmail: creds?.client_email ?? null,
          quotaProjectId: creds?.quota_project_id ?? null,
          accessToken: tokenPresent ? "present" : "absent",
        });
      } catch (e) {
        logger.warn("⚠️ GoogleAuth credentials snapshot failed", {
          ts: nowIso(),
          uid,
          runtimeProjectId: getRuntimeProjectId(),
          message: e?.message ?? String(e),
          stack: e?.stack ?? null,
        });
      }

      let purchase;
      try {
        purchase = await androidPublisher.purchases.products.get({
          packageName: PACKAGE_NAME,
          productId: pid,
          token: purchaseToken,
        });
      } catch (e) {
        const status = e?.response?.status ?? null;
        const statusText = e?.response?.statusText ?? null;
        const responseData = e?.response?.data ?? null;

        logger.error("❌ Play API purchases.products.get falhou", {
          uid,
          productId: pid,
          message: e?.message ?? String(e),
          code: e?.code ?? null,
          status,
          statusText,
          responseData,
          errors: e?.errors ?? null,
          stack: e?.stack ?? null,
        });

        throw new HttpsError(
          "failed-precondition",
          "Não foi possível validar a compra na Play. Verifique app/sku/token e permissões da conta de serviço no Play Console."
        );
      }

      const data = purchase?.data || {};

      logger.info("📦 Resposta Play", {
        uid,
        productId: pid,
        orderId: data.orderId ?? null,
        purchaseState: data.purchaseState ?? null,
        acknowledgementState: data.acknowledgementState ?? null,
        purchaseTimeMillis: data.purchaseTimeMillis ?? null,
        consumptionState: data.consumptionState ?? null,
      });

      if (data.purchaseState !== 0) {
        throw new HttpsError("failed-precondition", "Compra não concluída.");
      }

      try {
        if (data.acknowledgementState === 0) {
          await androidPublisher.purchases.products.acknowledge({
            packageName: PACKAGE_NAME,
            productId: pid,
            token: purchaseToken,
          });
          logger.info("✅ Compra acknowledged", { uid, productId: pid });
        } else {
          logger.info("ℹ️ Compra já estava acknowledged", { uid, productId: pid });
        }
      } catch (e) {
        const status = e?.response?.status ?? null;
        const statusText = e?.response?.statusText ?? null;
        const responseData = e?.response?.data ?? null;

        logger.error("❌ Falha ao acknowledge", {
          uid,
          productId: pid,
          message: e?.message ?? String(e),
          code: e?.code ?? null,
          status,
          statusText,
          responseData,
          errors: e?.errors ?? null,
          stack: e?.stack ?? null,
        });

        throw new HttpsError(
          "internal",
          "Falha ao confirmar (acknowledge) a compra na Play. Tente novamente."
        );
      }

      try {
        await admin.auth().setCustomUserClaims(uid, {
          sessionValid: true,
          basePlan: "basico",
          addons: [],
        });
      } catch (e) {
        logger.error("❌ Falha ao setar custom claims pós-compra", {
          uid,
          message: e?.message ?? String(e),
          stack: e?.stack ?? null,
        });
        throw new HttpsError("internal", "Falha ao liberar acesso (claims).");
      }

      try {
        const purchasedAtMillis = Number(data.purchaseTimeMillis);
        const purchasedAt =
          Number.isFinite(purchasedAtMillis) && purchasedAtMillis > 0
            ? admin.firestore.Timestamp.fromMillis(purchasedAtMillis)
            : admin.firestore.FieldValue.serverTimestamp();

        await admin.firestore().collection("users").doc(uid).set(
          {
            basePlan: "basico",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            lastPurchase: {
              productId: pid,
              platform: "android",
              orderId: data.orderId ?? null,
              purchasedAt,
            },
          },
          { merge: true }
        );
      } catch (e) {
        logger.error("❌ Falha ao atualizar Firestore pós-compra", {
          uid,
          message: e?.message ?? String(e),
          stack: e?.stack ?? null,
        });
        throw new HttpsError("internal", "Falha ao registrar compra no banco.");
      }

      logger.info("🎉 Plano básico liberado", { uid, productId: pid });

      return {
        success: true,
        orderId: data.orderId ?? null,
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        logger.error("❌ claimPurchase HttpsError", {
          code: error.code,
          message: error.message,
          details: error.details ?? null,
          ts: nowIso(),
          runtimeProjectId: getRuntimeProjectId(),
        });
        throw error;
      }

      logger.error("❌ claimPurchase erro não tratado", {
        message: error?.message ?? String(error),
        stack: error?.stack ?? null,
        ts: nowIso(),
        runtimeProjectId: getRuntimeProjectId(),
      });

      throw new HttpsError("internal", "Erro interno ao validar compra.");
    }
  }
);

// =====================================================
// ================== DELETE ACCOUNT (v2) ===============
// =====================================================
exports.deleteAccount = require("./delete_account").deleteAccount;