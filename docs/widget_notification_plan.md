# 위젯/알림 기본 설계 (요약)

## 홈/앱 위젯 데이터 모델
- **입력 소스**: Firestore 동기 후 로컬 캐시(Hive/Prefs)에서 가볍게 읽어오기.
- **공통 구조**:
  - `date`: YYYY-MM-DD (오늘 기준)
  - `todos`: 최대 N개 요약 `{id, title, isDone, textTime, color}`
  - `events`: 오늘 일정/메모 요약 `{title, timeText?, color}`
  - `lastUpdated`: ISO8601
- **플랫폼별**
  - iOS WidgetKit: `AppGroup` 경로에 JSON 스냅샷 저장 → 타임라인에서 decode.
  - Android AppWidget: `SharedPreferences`/`Glance`용 데이터 클래스로 변환 후 RemoteViews/Glance 렌더.

## 로컬 알림 예약/반복 설계
- **기본 트리거**: 투두 `dueTime` 또는 위젯 데이터 스냅샷 생성 시 함께 스케줄.
- **모델**: `{id, title, body, scheduledAt, repeatRule?, payload(date/id), channelId}`
- **반복**: 주간 반복은 BYDAY 기반으로 요일 배열, 연간/월간 반복은 BYMONTH/BYMONTHDAY 저장.
- **예약 타이밍**:
  - 앱 진입/동기 완료 시: 미래 7일치 스케줄 재생성.
  - 투두/반복일정 수정 시: 해당 id의 알림 취소 후 재등록.
- **에러/권한**: 권한 거부 시 UI 피드백, 재시도는 동기 시점마다 상태 확인 후 필요한 알림만 재등록.
