import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as crypto from "crypto";


const PC_LINK_PEPPER = defineSecret("PC_LINK_PEPPER");

admin.initializeApp();
const db = admin.firestore();

function sha256Hex(input: string) {
  return crypto.createHash("sha256").update(input).digest("hex");
}

function makeSecret() {
  return crypto.randomBytes(32).toString("hex");
}

function makeHashFromSecret(secret: string) {
  return sha256Hex(secret + PC_LINK_PEPPER.value());
}

function nowTs() {
  return admin.firestore.Timestamp.now();
}

function addMinutes(ts: admin.firestore.Timestamp, minutes: number) {
  const ms = ts.toMillis() + minutes * 60_000;
  return admin.firestore.Timestamp.fromMillis(ms);
}

export const issuePcLinkKey = onCall({ secrets: [PC_LINK_PEPPER] }, async (request) => {

  const auth = request.auth;
  if (!auth?.uid) {
    throw new HttpsError("unauthenticated", "Login required.");
  }

  const uid = auth.uid;
  const ttlMinutes = Number(request.data?.ttlMinutes ?? 20);
  const safeTtl = Math.min(Math.max(ttlMinutes, 5), 60);

  const secret = makeSecret();
  const hash = makeHashFromSecret(secret);

  const createdAt = nowTs();
  const expiresAt = addMinutes(createdAt, safeTtl);

  const docRef = db.collection("deviceSecretsByHash").doc(hash);

  await docRef.set({
    uid,
    active: true,
    createdAt,
    revokedAt: null,
    expiresAt,
    deviceId: null,
    usedAt: null,
    failCount: 0,
    lastFailAt: null,
  });

  return { secret, expiresAt };
});

export const linkPcWithKey = onCall({ secrets: [PC_LINK_PEPPER] }, async (request) => {
  const secret = String(request.data?.secret ?? "").trim();
  const deviceId = String(request.data?.deviceId ?? "").trim();
  const platform = String(request.data?.platform ?? "").trim();

  if (!secret || secret.length < 20) {
    throw new HttpsError("invalid-argument", "Invalid secret.");
  }
  if (!deviceId || deviceId.length < 8) {
    throw new HttpsError("invalid-argument", "Invalid deviceId.");
  }
  if (!platform) {
    throw new HttpsError("invalid-argument", "Invalid platform.");
  }

  const hash = makeHashFromSecret(secret);
  const docRef = db.collection("deviceSecretsByHash").doc(hash);

  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(docRef);

    if (!snap.exists) {
      throw new HttpsError("not-found", "Key not found.");
    }

    const data = snap.data() as any;
    const expiresAt: admin.firestore.Timestamp | null = data.expiresAt ?? null;
    const active: boolean = !!data.active;

    const now = nowTs();
    if (!active) {
      throw new HttpsError("permission-denied", "Key is not active.");
    }
    if (!expiresAt || expiresAt.toMillis() < now.toMillis()) {
      tx.update(docRef, { active: false, revokedAt: now });
      throw new HttpsError("deadline-exceeded", "Key expired.");
    }

    const failCount: number = Number(data.failCount ?? 0);
    const lastFailAt: admin.firestore.Timestamp | null = data.lastFailAt ?? null;

    if (failCount >= 5 && lastFailAt) {
      const lockUntil = admin.firestore.Timestamp.fromMillis(
        lastFailAt.toMillis() + 10 * 60_000
      );
      if (lockUntil.toMillis() > now.toMillis()) {
        throw new HttpsError("resource-exhausted", "Too many attempts. Try later.");
      }
    }

    const uid: string = data.uid;
    if (!uid) {
      throw new HttpsError("internal", "Corrupted key data.");
    }

    tx.update(docRef, {
      active: false,
      usedAt: now,
      deviceId,
    });

    const deviceRef = db.doc(`users/${uid}/devices/${deviceId}`);
    const deviceSnap = await tx.get(deviceRef);

    if (!deviceSnap.exists) {
      tx.set(deviceRef, {
        deviceId,
        nickname: "Unnamed PC",
        platform,
        createdAt: now,
        lastSeenAt: now,
        revokedAt: null,
        status: "active",
      });
    } else {
      tx.update(deviceRef, {
        platform,
        lastSeenAt: now,
        status: "active",
        revokedAt: null,
      });
    }

    return { uid };
  });

  const customToken = await admin.auth().createCustomToken(result.uid, {
    deviceId,
  });

  return { customToken };
  
});

export const revokeDevice = onCall(async (request) => {
  const auth = request.auth;
  if (!auth?.uid) {
    throw new HttpsError("unauthenticated", "Login required.");
  }

  const uid = auth.uid;
  const deviceId = String(request.data?.deviceId ?? "").trim();
  if (!deviceId || deviceId.length < 8) {
    throw new HttpsError("invalid-argument", "Invalid deviceId.");
  }

  const now = admin.firestore.Timestamp.now();
  const deviceRef = db.doc(`users/${uid}/devices/${deviceId}`);
  const userRef = db.doc(`users/${uid}`);

  await db.runTransaction(async (tx) => {
    const deviceSnap = await tx.get(deviceRef);
    if (!deviceSnap.exists) {
      // 없는 deviceId를 revoke하려는 경우
      throw new HttpsError("not-found", "Device not found.");
    }

    // devices 상태 revoke
    tx.update(deviceRef, {
      status: "revoked",
      revokedAt: now,
      lastSeenAt: now, // optional
    });

    // 논리적 토큰 무효화 트리거: tokenVersion 증가
    const userSnap = await tx.get(userRef);
    const cur = userSnap.exists ? Number((userSnap.data() as any).tokenVersion ?? 0) : 0;

    tx.set(
      userRef,
      {
        tokenVersion: cur + 1,
        tokenVersionUpdatedAt: now,
      },
      { merge: true }
    );
  });

  return { ok: true };
});
