import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";

admin.initializeApp();

export const registerSession = onCall(
  { region: "us-central1" },
  async (request) => {
    const uid = request.auth?.uid;
    const deviceIdRaw = request.data?.deviceId;

    if (!uid) {
      throw new HttpsError("unauthenticated", "Não autorizado.");
    }

    if (typeof deviceIdRaw !== "string" || deviceIdRaw.trim().length < 8) {
      throw new HttpsError("invalid-argument", "deviceId inválido.");
    }

    const deviceId = deviceIdRaw.trim();

    const db = admin.firestore();

    // ================= LÊ USER =================
    const userRef = db.collection("users").doc(uid);
    const userSnap = await userRef.get();

    const userData = userSnap.exists ? userSnap.data() : {};
    const basePlan = (userData?.basePlan as string) ?? "gratis";
    const addons = Array.isArray(userData?.addons) ? userData?.addons : [];

    // ================= ESCREVE SESSÃO + DEVICE ATIVO =================
    // ✅ IMPORTANTÍSSIMO: atualizar "users.deviceIdAtivo" porque é o que o app usa no SessionGuard
    // ✅ Mantém também um histórico/controle em "user_sessions" se você quiser
    const sessionRef = db.collection("user_sessions").doc(uid);

    await Promise.all([
      sessionRef.set(
        {
          deviceId,
          lastLoginAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      ),
      userRef.set(
        {
          deviceIdAtivo: deviceId,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      ),
    ]);

    // ================= AUTH CLAIMS =================
    await admin.auth().setCustomUserClaims(uid, {
      sessionValid: true,
      basePlan,
      addons,
    });

    // ❌ NÃO revogar refresh tokens aqui.
    // Isso pode causar UNAUTHENTICATED no app ao tentar getIdToken(true),
    // principalmente durante compra/restore.

    return { success: true };
  }
);