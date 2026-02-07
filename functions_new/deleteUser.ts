import { onCall } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

admin.initializeApp();

// ============================================
// DELETE USER (AUTH + FIRESTORE)
// ============================================
export const deleteUser = onCall(async (request) => {
  // 🔐 Verifica autenticação
  if (!request.auth) {
    throw new Error("Usuário não autenticado");
  }

  const uid = request.auth.uid;
  console.log("🧠 DELETE_USER -> UID:", uid);

  try {
    // 🔥 Apaga Firestore
    await admin.firestore().collection("users").doc(uid).delete();
    console.log("✅ Firestore user deleted");

    // 🔥 Apaga Firebase Auth
    await admin.auth().deleteUser(uid);
    console.log("✅ FirebaseAuth user deleted");

    return { success: true };
  } catch (e) {
    console.error("❌ DELETE_USER ERROR:", e);
    throw new Error("Erro ao deletar usuário");
  }
});
