# IAP (크레딧) 배포 체크리스트

## 0) 전제
- Android: Google Play Billing (consumable)
- iOS: StoreKit (consumable)
- 상품 ID: `credit_1000`, `credit_5000`, `credit_10000`, `credit_50000`

## 1) 스토어 콘솔 작업 (수동)
### Google Play Console
1. 앱 생성/등록 + 내부 테스트 트랙 준비
2. **인앱 상품(관리형/소모형)** 4개 생성
3. `Setup > API access`에서 Google Cloud 프로젝트 연동
4. Google Cloud 콘솔에서 **Google Play Android Developer API** 활성화
5. Functions 런타임 서비스계정에 Play Console 권한 부여
   - Gen2 기본값은 보통: `<PROJECT_NUMBER>-compute@developer.gserviceaccount.com`

### App Store Connect
1. 앱 생성/등록 + Sandbox tester 준비
2. **Consumable IAP** 4개 생성
3. Xcode에서 In-App Purchase Capability 활성화
4. App Store Connect에서 계약/세금/은행 정보 완료

## 2) Functions 환경 설정
### (A) `.env` (비밀 아님)
`functions/.env`:
- `ANDROID_PACKAGE_NAME=...` (Android `applicationId`)
- `IOS_BUNDLE_ID=...` (iOS bundle id)
- `DEBUG_COUPON_ALLOW_EMAILS=...` (선택, 디버그 쿠폰 허용 이메일 목록: `a@b.com,c@d.com`)

### (B) Secret Manager (비밀)
Apple 공유 시크릿 등록:
```bash
firebase functions:secrets:set APPLE_IAP_SHARED_SECRET --data-file - --project dayscript-746bd
```
- Windows PowerShell: 입력 후 종료는 `Ctrl+Z` → `Enter`

## 3) 배포
```bash
firebase deploy --only functions,firestore:rules --project dayscript-746bd
```

## 4) 테스트 시나리오
1. (모바일) 크레딧 충전 → 성공 후 크레딧 잔액 증가 확인
2. (모바일) Pro/Premium 구독 구매 → 크레딧 차감 + 남은 일수 증가 확인
3. (모바일) Premium+Pro 동시 보유 → Premium 먼저 차감되는지 확인
4. (게스트) 결제/구독 진입 시 “게스트 불가 + 로그인 버튼” 노출 확인
5. (지연/중단) 결제 도중 앱 종료/네트워크 끊김 후 재실행 → 구매가 재처리되는지 확인
