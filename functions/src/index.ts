import * as admin from "firebase-admin";
import { onCall } from "firebase-functions/v2/https";

admin.initializeApp();

export const registerSession = onCall(async (request) => {
  const uid = request.auth?.uid;
  const deviceId = request.data.deviceId;

  if (!uid || !deviceId) {
    throw new Error("Não autorizado");
  }

  // ================= SESSION =================

  const sessionRef = admin
    .firestore()
    .collection("user_sessions")
    .doc(uid);

  await sessionRef.set({
    deviceId,
    lastLoginAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // ================= USER DATA =================
  // 🔐 fonte de verdade do plano
  const userDoc = await admin
    .firestore()
    .collection("users")
    .doc(uid)
    .get();

  const userData = userDoc.exists ? userDoc.data() : {};

  const basePlan = userData?.basePlan ?? "gratis";
  const addons = userData?.addons ?? [];

  // ================= AUTH CLAIMS =================

  await admin.auth().setCustomUserClaims(uid, {
    sessionValid: true,
    basePlan,
    addons,
  });

  // 🔥 invalida tokens antigos (força refresh)
  await admin.auth().revokeRefreshTokens(uid);

  return { success: true };
});
