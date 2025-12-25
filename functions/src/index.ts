import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret, defineString } from "firebase-functions/params";
import * as crypto from "crypto";
import { google } from "googleapis";


const PC_LINK_PEPPER = defineSecret("PC_LINK_PEPPER");
const APPLE_IAP_SHARED_SECRET = defineSecret("APPLE_IAP_SHARED_SECRET");
const IOS_BUNDLE_ID = defineString("IOS_BUNDLE_ID");
const ANDROID_PACKAGE_NAME = defineString("ANDROID_PACKAGE_NAME");
const DEBUG_COUPON_ALLOW_EMAILS = defineString("DEBUG_COUPON_ALLOW_EMAILS");

admin.initializeApp();
const db = admin.firestore();

function sha256Hex(input: string) {
  return crypto.createHash("sha256").update(input).digest("hex");
}

function couponCodeHash(code: string) {
  return sha256Hex(code.trim().toLowerCase());
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
  const nicknameRaw = request.data?.nickname;
  const nickname = typeof nicknameRaw === "string" ? nicknameRaw.trim() : "";

  if (!secret || secret.length < 20) throw new HttpsError("invalid-argument", "Invalid secret.");
  if (!deviceId || deviceId.length < 8) throw new HttpsError("invalid-argument", "Invalid deviceId.");
  if (!platform) throw new HttpsError("invalid-argument", "Invalid platform.");
  if (nickname && nickname.length > 30) throw new HttpsError("invalid-argument", "Nickname too long.");

  const hash = makeHashFromSecret(secret);
  const keyRef = db.collection("deviceSecretsByHash").doc(hash);
  // Phase 1: claim the key (read first, then write). Do NOT create the device doc yet.
  const claim = await db.runTransaction(async (tx) => {
    const keySnap = await tx.get(keyRef);
    if (!keySnap.exists) throw new HttpsError("not-found", "Key not found.");

    const data = keySnap.data() as any;
    const uid: string = String(data.uid ?? "");
    if (!uid) throw new HttpsError("internal", "Corrupted key data.");

    const now = nowTs();
    const expiresAt: admin.firestore.Timestamp | null = data.expiresAt ?? null;
    const active: boolean = !!data.active;

    if (!active) throw new HttpsError("permission-denied", "Key is not active.");

    const expired = !expiresAt || expiresAt.toMillis() < now.toMillis();
    if (expired) {
      tx.update(keyRef, { active: false, revokedAt: now });
      return { uid, claimed: false as const, expired: true as const };
    }

    tx.update(keyRef, {
      active: false,
      usedAt: now,
      deviceId,
      linkState: "claimed",
      tokenIssuedAt: null,
    });

    return { uid, claimed: true as const, expired: false as const };
  });

  if (claim.expired) {
    throw new HttpsError("deadline-exceeded", "Key expired.");
  }

  let customToken: string;
  try {
    customToken = await admin.auth().createCustomToken(claim.uid, { deviceId });
  } catch (e: any) {
    // Best-effort rollback so the key isn't consumed when token signing fails.
    try {
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(keyRef);
        if (!snap.exists) return;
        const d = snap.data() as any;
        if (d?.deviceId === deviceId && d?.linkState === "claimed") {
          tx.update(keyRef, {
            active: true,
            usedAt: null,
            deviceId: null,
            linkState: null,
            tokenIssuedAt: null,
          });
        }
      });
    } catch (_) {}

    const msg = String(e?.message ?? e ?? "Token signing failed.");
    throw new HttpsError("failed-precondition", msg);
  }

  // Phase 2: finalize device upsert (reads first, then writes).
  await db.runTransaction(async (tx) => {
    const deviceRef = db.doc(`users/${claim.uid}/devices/${deviceId}`);
    const deviceSnap = await tx.get(deviceRef);

    const keySnap = await tx.get(keyRef);
    if (!keySnap.exists) throw new HttpsError("not-found", "Key not found.");
    const keyData = keySnap.data() as any;
    if (keyData?.deviceId !== deviceId || keyData?.linkState !== "claimed") {
      throw new HttpsError("permission-denied", "Key state mismatch.");
    }

    const now = nowTs();

    if (!deviceSnap.exists) {
      tx.set(deviceRef, {
        deviceId,
        nickname: nickname || "Unnamed PC",
        platform,
        createdAt: now,
        lastSeenAt: now,
        revokedAt: null,
        status: "active",
      });
    } else {
      tx.update(deviceRef, {
        platform,
        ...(nickname ? { nickname } : {}),
        lastSeenAt: now,
        status: "active",
        revokedAt: null,
      });
    }

    tx.update(keyRef, { linkState: "used", tokenIssuedAt: now });
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
    // IMPORTANT: In Firestore transactions, all reads must occur before any writes.
    const deviceSnap = await tx.get(deviceRef);
    if (!deviceSnap.exists) {
      // 없는 deviceId를 revoke하려는 경우
      throw new HttpsError("not-found", "Device not found.");
    }

    const userSnap = await tx.get(userRef);
    const cur = userSnap.exists
      ? Number((userSnap.data() as any).tokenVersion ?? 0)
      : 0;
    // Remove from list: delete the device doc.
    tx.delete(deviceRef);

    // 논리적 토큰 무효화 트리거: tokenVersion 증가
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

// -----------------------------------------------------------------------------
// Billing: IAP credits + credit-based subscriptions
// -----------------------------------------------------------------------------

const CREDIT_PRODUCTS: Record<string, number> = {
  credit_1000: 100,
  credit_5000: 500,
  credit_10000: 1000,
  credit_50000: 5000,
};

const SUBSCRIPTION_PACKS: Record<
  string,
  Record<number, { costCredits: number; seconds: number }>
> = {
  pro: {
    7: { costCredits: 70, seconds: 7 * 86400 },
    30: { costCredits: 340, seconds: 30 * 86400 },
    100: { costCredits: 990, seconds: 100 * 86400 },
  },
  premium: {
    7: { costCredits: 120, seconds: 7 * 86400 },
    30: { costCredits: 620, seconds: 30 * 86400 },
    100: { costCredits: 1590, seconds: 100 * 86400 },
  },
};

function assertAuthedNonAnonymous(request: any) {
  const auth = request.auth;
  if (!auth?.uid) throw new HttpsError("unauthenticated", "Login required.");
  const provider = auth.token?.firebase?.sign_in_provider;
  if (provider === "anonymous") {
    throw new HttpsError("permission-denied", "Guest users cannot purchase.");
  }
  return auth.uid as string;
}

async function verifyGooglePlayProductPurchase(params: {
  packageName: string;
  productId: string;
  purchaseToken: string;
}): Promise<{ transactionId: string; purchaseTimeMillis?: string }> {
  const auth = new google.auth.GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/androidpublisher"],
  });
  const androidpublisher = google.androidpublisher({
    version: "v3",
    auth,
  });

  const resp = await androidpublisher.purchases.products.get({
    packageName: params.packageName,
    productId: params.productId,
    token: params.purchaseToken,
  });

  const data: any = resp.data;
  // purchaseState: 0 Purchased, 1 Canceled, 2 Pending
  const purchaseState = Number(data?.purchaseState ?? 0);
  if (purchaseState !== 0) {
    throw new HttpsError("failed-precondition", "Purchase is not completed.");
  }

  const orderId = String(data?.orderId ?? "").trim();
  const tx = orderId || params.purchaseToken;
  return { transactionId: tx, purchaseTimeMillis: data?.purchaseTimeMillis };
}

type AppleVerifyResponse = {
  status?: number;
  receipt?: {
    bundle_id?: string;
    in_app?: Array<{
      product_id?: string;
      transaction_id?: string;
      purchase_date_ms?: string;
    }>;
  };
  latest_receipt_info?: Array<{
    product_id?: string;
    transaction_id?: string;
    purchase_date_ms?: string;
  }>;
};

async function postAppleVerifyReceipt(
  url: string,
  body: Record<string, any>
): Promise<AppleVerifyResponse> {
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  return (await res.json()) as AppleVerifyResponse;
}

async function verifyAppleReceipt(params: {
  receiptBase64: string;
  productId: string;
  expectedBundleId: string;
  sharedSecret: string;
  purchaseId?: string;
}): Promise<{ transactionIds: string[] }> {
  const body = {
    "receipt-data": params.receiptBase64,
    password: params.sharedSecret,
    "exclude-old-transactions": true,
  };

  const prodUrl = "https://buy.itunes.apple.com/verifyReceipt";
  const sandboxUrl = "https://sandbox.itunes.apple.com/verifyReceipt";

  let resp = await postAppleVerifyReceipt(prodUrl, body);
  if (resp.status === 21007) {
    resp = await postAppleVerifyReceipt(sandboxUrl, body);
  }

  if (resp.status !== 0) {
    throw new HttpsError(
      "failed-precondition",
      `Apple receipt invalid (status=${resp.status}).`
    );
  }

  const bundleId = String(resp.receipt?.bundle_id ?? "");
  if (params.expectedBundleId && bundleId && bundleId !== params.expectedBundleId) {
    throw new HttpsError("permission-denied", "Bundle ID mismatch.");
  }

  const items = [
    ...(resp.latest_receipt_info ?? []),
    ...((resp.receipt?.in_app ?? []) as any[]),
  ];

  const filtered = items.filter(
    (it) => String(it?.product_id ?? "") === params.productId
  );
  if (filtered.length === 0) {
    throw new HttpsError("not-found", "Transaction not found in receipt.");
  }

  const sorted = filtered
    .slice()
    .sort(
      (a, b) => Number(b?.purchase_date_ms ?? 0) - Number(a?.purchase_date_ms ?? 0)
    );

  const ids: string[] = [];
  const seen = new Set<string>();
  for (const it of sorted) {
    const id = String(it?.transaction_id ?? "").trim();
    if (!id || seen.has(id)) continue;
    seen.add(id);
    ids.push(id);
  }

  if (ids.length === 0) throw new HttpsError("not-found", "Missing transaction_id.");

  if (params.purchaseId) {
    const idx = ids.indexOf(params.purchaseId);
    if (idx > 0) {
      const picked = ids.splice(idx, 1)[0];
      ids.unshift(picked);
    }
  }

  return { transactionIds: ids };
}

export const verifyIapCreditPurchase = onCall(
  {
    secrets: [APPLE_IAP_SHARED_SECRET],
  },
  async (request) => {
    const uid = assertAuthedNonAnonymous(request);

    const platform = String(request.data?.platform ?? "").trim();
    const productId = String(request.data?.productId ?? "").trim();
    const serverVerificationData = String(request.data?.serverVerificationData ?? "").trim();
    const purchaseIdRaw = request.data?.purchaseId;
    const purchaseId = typeof purchaseIdRaw === "string" ? purchaseIdRaw.trim() : undefined;

    if (!productId || !(productId in CREDIT_PRODUCTS)) {
      throw new HttpsError("invalid-argument", "Unknown productId.");
    }
    if (!serverVerificationData) {
      throw new HttpsError("invalid-argument", "Missing serverVerificationData.");
    }

    const grantedCredits = CREDIT_PRODUCTS[productId] ?? 0;
    if (grantedCredits <= 0) throw new HttpsError("internal", "Invalid credit mapping.");

    let transactionId = "";
    let iosTransactionCandidates: string[] = [];
    if (platform === "android") {
      const packageName = String(ANDROID_PACKAGE_NAME.value() ?? "").trim();
      if (!packageName) {
        throw new HttpsError("failed-precondition", "ANDROID_PACKAGE_NAME not set.");
      }
      const verified = await verifyGooglePlayProductPurchase({
        packageName,
        productId,
        purchaseToken: serverVerificationData,
      });
      transactionId = verified.transactionId;
    } else if (platform === "ios") {
      const bundleId = String(IOS_BUNDLE_ID.value() ?? "").trim();
      if (!bundleId) {
        throw new HttpsError("failed-precondition", "IOS_BUNDLE_ID not set.");
      }
      const secret = APPLE_IAP_SHARED_SECRET.value();
      if (!secret) {
        throw new HttpsError("failed-precondition", "APPLE_IAP_SHARED_SECRET not set.");
      }
      const verified = await verifyAppleReceipt({
        receiptBase64: serverVerificationData,
        productId,
        expectedBundleId: bundleId,
        sharedSecret: secret,
        purchaseId,
      });
      iosTransactionCandidates = verified.transactionIds;
      if (iosTransactionCandidates.length === 0) {
        throw new HttpsError("not-found", "No transaction candidates.");
      }
    } else {
      throw new HttpsError("invalid-argument", "Unsupported platform.");
    }

    const userRef = db.doc(`users/${uid}`);

    const result = await db.runTransaction(async (tx) => {
      const userSnap = await tx.get(userRef);
      const curBalance = userSnap.exists
        ? Number((userSnap.data() as any)?.creditBalance ?? 0)
        : 0;

      let effectiveTransactionId = transactionId;
      let ledgerRef = userRef.collection("iapLedger").doc(`${platform}_${effectiveTransactionId}`);

      if (platform === "ios") {
        effectiveTransactionId = "";
        ledgerRef = userRef.collection("iapLedger").doc("ios__uninitialized");

        for (const candidate of iosTransactionCandidates) {
          const ref = userRef.collection("iapLedger").doc(`ios_${candidate}`);
          const snap = await tx.get(ref);
          if (!snap.exists) {
            effectiveTransactionId = candidate;
            ledgerRef = ref;
            break;
          }
        }

        if (!effectiveTransactionId) {
          // All candidate transactions are already processed.
          return {
            creditBalance: curBalance,
            grantedCredits: 0,
            alreadyProcessed: true,
            transactionId: iosTransactionCandidates[0] ?? "",
          };
        }
      } else {
        if (!effectiveTransactionId) {
          throw new HttpsError("internal", "Missing transactionId.");
        }
        ledgerRef = userRef.collection("iapLedger").doc(`${platform}_${effectiveTransactionId}`);
        const ledgerSnap = await tx.get(ledgerRef);
        if (ledgerSnap.exists) {
          return {
            creditBalance: curBalance,
            grantedCredits: 0,
            alreadyProcessed: true,
            transactionId: effectiveTransactionId,
          };
        }
      }

      const nextBalance = curBalance + grantedCredits;

      tx.set(
        userRef,
        {
          creditBalance: nextBalance,
          creditUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      tx.set(ledgerRef, {
        uid,
        platform,
        productId,
        grantedCredits,
        transactionId: effectiveTransactionId,
        purchaseId: purchaseId ?? null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {
        creditBalance: nextBalance,
        grantedCredits,
        alreadyProcessed: false,
        transactionId: effectiveTransactionId,
      };
    });

    return result;
  }
);

type EntitlementWire = {
  proSeconds: number;
  premiumSeconds: number;
  lastAccruedAt: admin.firestore.Timestamp;
};

function parseEntitlement(raw: any): EntitlementWire {
  const proSeconds = Number(raw?.proSeconds ?? 0);
  const premiumSeconds = Number(raw?.premiumSeconds ?? 0);
  const lastAccruedAt =
    raw?.lastAccruedAt instanceof admin.firestore.Timestamp
      ? (raw.lastAccruedAt as admin.firestore.Timestamp)
      : admin.firestore.Timestamp.fromDate(new Date(0));
  return {
    proSeconds: Math.max(0, Math.trunc(proSeconds)),
    premiumSeconds: Math.max(0, Math.trunc(premiumSeconds)),
    lastAccruedAt,
  };
}

function balanceEntitlement(ent: EntitlementWire, now: admin.firestore.Timestamp) {
  const elapsedSeconds = Math.max(
    0,
    Math.floor((now.toMillis() - ent.lastAccruedAt.toMillis()) / 1000)
  );
  const premiumRemaining = Math.max(0, ent.premiumSeconds - elapsedSeconds);
  const leftover = Math.max(0, elapsedSeconds - ent.premiumSeconds);
  const proRemaining = Math.max(0, ent.proSeconds - leftover);
  return { proRemaining, premiumRemaining };
}

export const buySubscriptionWithCredits = onCall(async (request) => {
  const uid = assertAuthedNonAnonymous(request);
  const tier = String(request.data?.tier ?? "").trim();
  const days = Number(request.data?.days ?? 0);

  if (!(tier in SUBSCRIPTION_PACKS)) throw new HttpsError("invalid-argument", "Invalid tier.");
  if (!Number.isFinite(days) || days <= 0) throw new HttpsError("invalid-argument", "Invalid days.");

  const pack = (SUBSCRIPTION_PACKS as any)[tier]?.[days];
  if (!pack) throw new HttpsError("invalid-argument", "Unknown subscription pack.");

  const userRef = db.doc(`users/${uid}`);
  const now = admin.firestore.Timestamp.now();

  const result = await db.runTransaction(async (tx) => {
    const userSnap = await tx.get(userRef);
    const data = userSnap.exists ? (userSnap.data() as any) : {};

    const curCredits = Number(data?.creditBalance ?? 0);
    if (curCredits < pack.costCredits) {
      throw new HttpsError("failed-precondition", "Insufficient credits.");
    }

    const ent = parseEntitlement(data?.entitlement ?? null);
    const b = balanceEntitlement(ent, now);

    const addPremium = tier === "premium" ? pack.seconds : 0;
    const addPro = tier === "pro" ? pack.seconds : 0;

    const nextEnt = {
      proSeconds: Math.max(0, b.proRemaining + addPro),
      premiumSeconds: Math.max(0, b.premiumRemaining + addPremium),
      lastAccruedAt: now,
    };

    const nextCredits = curCredits - pack.costCredits;
    tx.set(
      userRef,
      {
        creditBalance: nextCredits,
        creditUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        entitlement: nextEnt,
        entitlementUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return { creditBalance: nextCredits, entitlement: nextEnt };
  });

  return result;
});

function assertCouponAllowed(request: any) {
  const emailsRaw = String(DEBUG_COUPON_ALLOW_EMAILS.value() ?? "").trim();
  if (!emailsRaw) {
    throw new HttpsError(
      "failed-precondition",
      "Coupon feature is disabled (DEBUG_COUPON_ALLOW_EMAILS not set)."
    );
  }
  const allow = new Set(
    emailsRaw
      .split(",")
      .map((s) => s.trim().toLowerCase())
      .filter((s) => s.length > 0)
  );

  const email = String(request.auth?.token?.email ?? "").trim().toLowerCase();
  if (!email || !allow.has(email)) {
    throw new HttpsError("permission-denied", "Not allowed.");
  }
}

type CouponType = "credit" | "subDays";
type CouponTier = "pro" | "premium";
type CouponDoc = {
  type: CouponType;
  amount: number;
  tier?: CouponTier;
  maxRedemptions?: number;
  perUserLimit?: number;
  expiresAt?: admin.firestore.Timestamp | null;
  enabled?: boolean;
  campaign?: string | null;
  createdBy?: string | null;
  redemptionsCount?: number;
};

function parseCouponDoc(raw: any): CouponDoc {
  const typeRaw = String(raw?.type ?? "").trim();
  const type: CouponType = typeRaw === "credit" ? "credit" : "subDays";

  const amount = Math.trunc(Number(raw?.amount ?? 0));

  const tierRaw = String(raw?.tier ?? "").trim().toLowerCase();
  const tier: CouponTier | undefined =
    tierRaw === "pro" ? "pro" : tierRaw === "premium" ? "premium" : undefined;

  const enabled = raw?.enabled === undefined ? true : !!raw.enabled;
  const maxRedemptions =
    raw?.maxRedemptions === undefined ? undefined : Math.trunc(Number(raw.maxRedemptions));
  const perUserLimit =
    raw?.perUserLimit === undefined ? undefined : Math.trunc(Number(raw.perUserLimit));

  const expiresAt =
    raw?.expiresAt instanceof admin.firestore.Timestamp
      ? (raw.expiresAt as admin.firestore.Timestamp)
      : null;

  const campaign =
    raw?.campaign === undefined || raw?.campaign === null ? null : String(raw.campaign);
  const createdBy =
    raw?.createdBy === undefined || raw?.createdBy === null ? null : String(raw.createdBy);

  const redemptionsCount =
    raw?.redemptionsCount === undefined ? undefined : Math.trunc(Number(raw.redemptionsCount));

  return {
    type,
    amount,
    tier,
    enabled,
    maxRedemptions: maxRedemptions !== undefined && Number.isFinite(maxRedemptions) ? maxRedemptions : undefined,
    perUserLimit: perUserLimit !== undefined && Number.isFinite(perUserLimit) ? perUserLimit : undefined,
    expiresAt,
    campaign,
    createdBy,
    redemptionsCount: redemptionsCount !== undefined && Number.isFinite(redemptionsCount) ? redemptionsCount : undefined,
  };
}

export const redeemCoupon = onCall(async (request) => {
  const uid = assertAuthedNonAnonymous(request);

  const codeRaw = String(request.data?.code ?? "").trim();
  if (!codeRaw) throw new HttpsError("invalid-argument", "Missing code.");

  const codeHash = couponCodeHash(codeRaw);
  const couponRef = db.doc(`coupons/${codeHash}`);
  const userRef = db.doc(`users/${uid}`);
  const now = admin.firestore.Timestamp.now();

  const result = await db.runTransaction(async (tx) => {
    const [couponSnap, userSnap] = await Promise.all([tx.get(couponRef), tx.get(userRef)]);
    if (!couponSnap.exists) throw new HttpsError("not-found", "Coupon not found.");

    const coupon = parseCouponDoc(couponSnap.data() as any);
    const userData = userSnap.exists ? (userSnap.data() as any) : {};

    if (!coupon.enabled) throw new HttpsError("failed-precondition", "Coupon is disabled.");
    if (!Number.isFinite(coupon.amount) || coupon.amount === 0) {
      throw new HttpsError("failed-precondition", "Invalid coupon amount.");
    }
    if (coupon.type === "subDays" && !coupon.tier) {
      throw new HttpsError("failed-precondition", "Invalid coupon tier.");
    }
    if (coupon.expiresAt && coupon.expiresAt.toMillis() < now.toMillis()) {
      throw new HttpsError("deadline-exceeded", "Coupon expired.");
    }

    const nonce = Math.max(0, Math.trunc(Number(userData?.debugCouponResetNonce ?? 0)));
    const redeemKey = `${codeHash}_${uid}_${nonce}`;
    const redemptionRef = db.doc(`couponRedemptions/${redeemKey}`);

    const redemptionSnap = await tx.get(redemptionRef);
    if (redemptionSnap.exists) {
      const r = redemptionSnap.data() as any;
      return {
        alreadyRedeemed: true,
        codeHash,
        redeemKey,
        deltaCredits: Number(r?.deltaCredits ?? 0),
        deltaProSeconds: Number(r?.deltaProSeconds ?? 0),
        deltaPremiumSeconds: Number(r?.deltaPremiumSeconds ?? 0),
      };
    }

    const curCount = Math.max(0, Math.trunc(Number(coupon.redemptionsCount ?? 0)));
    const max = coupon.maxRedemptions;
    if (max !== undefined) {
      if (!Number.isFinite(max) || max <= 0) {
        throw new HttpsError("failed-precondition", "Invalid maxRedemptions.");
      }
      if (curCount >= max) throw new HttpsError("resource-exhausted", "Coupon fully redeemed.");
    }

    const perUserLimit = coupon.perUserLimit;
    if (perUserLimit !== undefined && perUserLimit !== 1) {
      throw new HttpsError("failed-precondition", "Only perUserLimit=1 is supported.");
    }

    let deltaCredits = 0;
    let deltaProSeconds = 0;
    let deltaPremiumSeconds = 0;

    if (coupon.type === "credit") {
      deltaCredits = coupon.amount;
    } else {
      const seconds = coupon.amount * 86400;
      if (coupon.tier === "pro") deltaProSeconds = seconds;
      if (coupon.tier === "premium") deltaPremiumSeconds = seconds;
    }

    const ent = parseEntitlement(userData?.entitlement ?? null);
    const b = balanceEntitlement(ent, now);

    const nextEnt = {
      proSeconds: Math.max(0, b.proRemaining + deltaProSeconds),
      premiumSeconds: Math.max(0, b.premiumRemaining + deltaPremiumSeconds),
      lastAccruedAt: now,
    };

    const curCredits = Math.trunc(Number(userData?.creditBalance ?? 0));
    const nextCredits = Math.max(0, curCredits + deltaCredits);

    tx.set(
      userRef,
      {
        creditBalance: nextCredits,
        creditUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        entitlement: nextEnt,
        entitlementUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    tx.set(redemptionRef, {
      uid,
      codeHash,
      redeemKey,
      debugCouponResetNonce: nonce,
      campaign: coupon.campaign ?? null,
      couponType: coupon.type,
      couponTier: coupon.tier ?? null,
      amount: coupon.amount,
      deltaCredits,
      deltaProSeconds,
      deltaPremiumSeconds,
      redeemedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    tx.set(
      couponRef,
      {
        redemptionsCount: curCount + 1,
        lastRedeemedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return {
      alreadyRedeemed: false,
      codeHash,
      redeemKey,
      deltaCredits,
      deltaProSeconds,
      deltaPremiumSeconds,
      creditBalance: nextCredits,
      entitlement: nextEnt,
    };
  });

  return result;
});

export const debugResetCouponRedemptionNonce = onCall(async (request) => {
  const uid = assertAuthedNonAnonymous(request);
  assertCouponAllowed(request);

  const userRef = db.doc(`users/${uid}`);
  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const data = snap.exists ? (snap.data() as any) : {};
    const cur = Math.max(0, Math.trunc(Number(data?.debugCouponResetNonce ?? 0)));
    const next = cur + 1;

    tx.set(
      userRef,
      {
        debugCouponResetNonce: next,
        debugCouponResetAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return { debugCouponResetNonce: next };
  });

  return result;
});

export const applyCoupon = onCall(async (request) => {
  const uid = assertAuthedNonAnonymous(request);
  assertCouponAllowed(request);

  const codeRaw = String(request.data?.code ?? "").trim();
  const code = codeRaw.toLowerCase();
  if (!code) throw new HttpsError("invalid-argument", "Missing code.");

  let addCredits = 0;
  let deltaProSeconds = 0;
  let deltaPremiumSeconds = 0;

  const d3 = 3 * 86400;
  switch (code) {
    case "credit1000":
      addCredits = 1000;
      break;
    case "proplanplus":
      deltaProSeconds = d3;
      break;
    case "proplanminus":
      deltaProSeconds = -d3;
      break;
    case "premiunplanplus":
      deltaPremiumSeconds = d3;
      break;
    case "premiunplanminus":
      deltaPremiumSeconds = -d3;
      break;
    default:
      throw new HttpsError("not-found", "Unknown coupon.");
  }

  const userRef = db.doc(`users/${uid}`);
  const now = admin.firestore.Timestamp.now();

  const result = await db.runTransaction(async (tx) => {
    const userSnap = await tx.get(userRef);
    const data = userSnap.exists ? (userSnap.data() as any) : {};

    const curCredits = Number(data?.creditBalance ?? 0);
    const ent = parseEntitlement(data?.entitlement ?? null);
    const b = balanceEntitlement(ent, now);

    const nextCredits = Math.max(0, Math.trunc(curCredits + addCredits));
    const nextPremium = Math.max(
      0,
      Math.trunc(b.premiumRemaining + deltaPremiumSeconds)
    );
    const nextPro = Math.max(0, Math.trunc(b.proRemaining + deltaProSeconds));

    const nextEnt = {
      proSeconds: nextPro,
      premiumSeconds: nextPremium,
      lastAccruedAt: now,
    };

    tx.set(
      userRef,
      {
        creditBalance: nextCredits,
        creditUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        entitlement: nextEnt,
        entitlementUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        couponDebugLastCode: code,
        couponDebugUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return { creditBalance: nextCredits, entitlement: nextEnt, code };
  });

  return result;
});


