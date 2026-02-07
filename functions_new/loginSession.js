/**
 * Firebase Functions v2 – Login Único por dispositivo
 */

const { onCall } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

admin.initializeApp();
setGlobalOptions({ maxInstances: 10 });

exports.loginSession = onCall(async (request) => {
  try {
    const context = request.auth;
    const { deviceId } = request.data;

    if (!context || !context.uid) {
      throw new Error("Usuário não autenticado.");
    }

    if (!deviceId) {
      throw new Error("deviceId não informado.");
    }

    const uid = context.uid;
    const userRef = admin.firestore().collection("users").doc(uid);
    const userSnap = await userRef.get();

    if (!userSnap.exists) {
      throw new Error("Usuário não encontrado no Firestore.");
    }

    const userData = userSnap.data();
    const currentDeviceId = userData.deviceId;

    // Mesmo dispositivo → mantém sessão
    if (currentDeviceId === deviceId) {
      await userRef.update({
        sessionValid: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return { success: true, sessionValid: true };
    }

    // Dispositivo diferente → invalida sessão antiga
    await userRef.update({
      deviceId: deviceId,
      sessionValid: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    logger.info(`Sessão sobrescrita para usuário ${uid}`);

    return { success: true, sessionValid: true };
  } catch (error) {
    logger.error("Erro em loginSession:", error);
    return { success: false, error: error.message };
  }
});
