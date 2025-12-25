# Coupon System (Server-Verified)

This project supports a **server-verified coupon** flow via Cloud Functions + Firestore.

## How it works
- Client enters a coupon code in-app.
- App calls Cloud Function `redeemCoupon`.
- Server:
  - hashes the code (`codeHash = sha256(lowercase(code))`)
  - loads `coupons/{codeHash}`
  - checks `enabled / expiresAt / maxRedemptions / perUserLimit`
  - writes an idempotent redemption record `couponRedemptions/{codeHash}_{uid}_{debugNonce}`
  - applies credits/subscription time to `users/{uid}` (server time)

Guest/anonymous users are blocked (server + UI).

## Firestore documents
### `coupons/{codeHash}`
Example fields:
```js
{
  enabled: true,
  type: "credit",            // "credit" | "subDays"
  amount: 1000,              // credits or days (can be negative)
  tier: "pro",               // required for "subDays": "pro" | "premium"
  maxRedemptions: 50,        // optional
  perUserLimit: 1,           // optional (currently supports only 1)
  redemptionsCount: 0,       // maintained by server
  expiresAt: Timestamp,      // optional
  campaign: "thanks_testers" // optional
}
```

### `couponRedemptions/{redeemKey}`
- Doc ID: `{codeHash}_{uid}_{debugCouponResetNonce}`
- Created by server on successful redemption (also acts as idempotency key).

## Creating a coupon (computing `codeHash`)
`codeHash` is `sha256(lowercase(code))`.

PowerShell example:
```powershell
$code = "credit1000"
$bytes = [Text.Encoding]::UTF8.GetBytes($code.ToLower())
$hashBytes = [Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
($hashBytes | ForEach-Object { $_.ToString("x2") }) -join ""
```

Use the output hex string as the Firestore doc ID under `coupons/`.

### Precomputed hashes (temporary debug list)
- `credit1000` => `6b3f5beeea6df79945f282b4692090145d651d8ae5ebad324b6e4fdc9261b53d`
- `proplanplus` => `e2f92b596bede4e42a9e76e1f7371caeb0ccf788378766a2454d296243d8df0f`
- `proplanminus` => `666e697805bab5e30c23d0fcdc8a4647ad18ae231b22adceb1cd1e001a5faeab`
- `premiunplanplus` => `643657ffcb35e672dbcab07bd6fbf87a28c7827c07e5909932ed9a7e79268210`
- `premiunplanminus` => `6f2754fc3781bac1996f4137dd14a9220dc84c602ff2f6c10f826649fbead602`

### Temporary debug coupon docs (recommended values)
- `credit1000`: `{ type: "credit", amount: 1000 }`
- `proplanplus`: `{ type: "subDays", tier: "pro", amount: 7 }`
- `proplanminus`: `{ type: "subDays", tier: "pro", amount: -7 }`
- `premiunplanplus`: `{ type: "subDays", tier: "premium", amount: 7 }`
- `premiunplanminus`: `{ type: "subDays", tier: "premium", amount: -7 }`

## Debug: "usage reset" (reusing the same coupon)
- User doc field: `users/{uid}.debugCouponResetNonce` (default `0`)
- Redemption idempotency key includes the nonce:
  - `redeemKey = codeHash + "_" + uid + "_" + debugCouponResetNonce`
- In **debug builds**, the coupon page shows a button that calls
  `debugResetCouponRedemptionNonce` to increment this nonce.
- Server only allows this reset for emails listed in `DEBUG_COUPON_ALLOW_EMAILS`.
