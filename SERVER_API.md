# MyPort 서버 API 초안

현재 `/Users/changminbyun/codex/MyPort/MyPortServer` 에 Railway 배포 기준 서버 구현이 포함되어 있습니다.

- 권장 저장 구조
  - 메타데이터: Postgres
  - 업로드 이미지: Railway Volume
- 분석 구조
  - 클라우드: OpenAI 이미지 분석
  - 로컬 macOS: Vision OCR fallback

## 공통

- Base path: `/v1`
- 인증: `Authorization: Bearer <token>`
- Content-Type: `application/json`
- 날짜 형식: ISO 8601

## 상태 확인

`GET /healthz`

인증 없이 호출할 수 있습니다.

응답:

```json
{
  "status": "ok",
  "mode": "postgres",
  "serverTime": "2026-03-25T10:00:00Z",
  "baseURL": "https://myport-api.up.railway.app",
  "dataDirectory": "/data/myport",
  "uploadsDirectory": "/data/myport/uploads",
  "analysisProvider": "openai",
  "analysisModel": "gpt-5.4-mini",
  "openAIConfigured": true,
  "databaseConfigured": true
}
```

## 1. 스냅샷 목록 조회

`GET /v1/snapshots`

선택적 쿼리:

- `from`
- `to`
- `limit`
- `sort=capturedAt:desc`
- `groupBy=month` (향후 확장)

응답:

```json
{
  "items": [
    {
      "id": "UUID",
      "title": "2026년 3월 포트폴리오",
      "capturedAt": "2026-03-25T10:00:00Z",
      "note": "월말 정리",
      "createdAt": "2026-03-25T10:01:00Z",
      "baseCurrency": "KRW",
      "holdings": [],
      "exchangeRates": [],
      "lastSyncedAt": "2026-03-25T10:01:00Z"
    }
  ]
}
```

## 2. 스냅샷 상세 조회

`GET /v1/snapshots/{snapshotId}`

응답:

```json
{
  "id": "UUID",
  "title": "2026년 3월 포트폴리오",
  "capturedAt": "2026-03-25T10:00:00Z",
  "note": "월말 정리",
  "createdAt": "2026-03-25T10:01:00Z",
  "baseCurrency": "KRW",
  "holdings": [],
  "exchangeRates": [],
  "lastSyncedAt": "2026-03-25T10:01:00Z"
}
```

## 2-1. 히스토리 타임라인 조회 (선택 확장)

MVP에서는 앱이 `GET /v1/snapshots` 결과로 직접 히스토리를 계산한다. 기록 수가 많아지면 다음 API를 추가할 수 있다.

`GET /v1/analytics/timeline?from=2026-01-01&to=2026-12-31&groupBy=month`

응답 예시:

```json
{
  "items": [
    {
      "snapshotId": "UUID",
      "capturedAt": "2026-03-25T10:00:00Z",
      "monthKey": "2026-03",
      "totalKRW": 18420000,
      "deltaKRWFromPrevious": 1280000
    }
  ]
}
```

## 3. 스냅샷 생성

`POST /v1/snapshots`

요청 본문:

```json
{
  "id": "UUID",
  "title": "수동 입력",
  "capturedAt": "2026-03-25T09:30:00Z",
  "note": "",
  "createdAt": "2026-03-25T09:31:00Z",
  "baseCurrency": "KRW",
  "holdings": [
    {
      "id": "UUID",
      "name": "Apple",
      "symbol": "AAPL",
      "institution": "키움증권",
      "assetClass": "foreignStock",
      "quantity": 10,
      "unitPrice": null,
      "marketValue": 1720,
      "currency": "USD",
      "country": "US",
      "memo": ""
    }
  ],
  "exchangeRates": [
    {
      "id": "UUID",
      "baseCurrency": "USD",
      "quoteCurrency": "KRW",
      "rateToQuote": 1472.3,
      "source": "manual",
      "observedAt": "2026-03-25T09:30:00Z"
    }
  ]
}
```

응답:

```json
{
  "id": "UUID",
  "title": "수동 입력",
  "capturedAt": "2026-03-25T09:30:00Z",
  "note": "",
  "createdAt": "2026-03-25T09:31:00Z",
  "baseCurrency": "KRW",
  "holdings": [],
  "exchangeRates": [],
  "lastSyncedAt": "2026-03-25T09:31:02Z"
}
```

## 4. 스냅샷 삭제

`DELETE /v1/snapshots/{snapshotId}`

응답:

- `204 No Content`

## 4-0. 스냅샷 수정

`PUT /v1/snapshots/{snapshotId}`

업로드 분석 후 검수 화면에서 제목, 메모, 환율, 보유 자산을 수정 저장할 때 사용합니다.

요청 본문:

- `POST /v1/snapshots`와 동일한 스냅샷 JSON

응답:

```json
{
  "id": "UUID",
  "title": "검수 완료 포트폴리오",
  "capturedAt": "2026-03-25T09:30:00Z",
  "note": "검수 저장 완료",
  "createdAt": "2026-03-25T09:31:00Z",
  "baseCurrency": "KRW",
  "holdings": [],
  "exchangeRates": [],
  "lastSyncedAt": "2026-03-25T09:35:00Z"
}
```

## 4-1. 스냅샷 비교 분석 조회 (선택 확장)

MVP에서는 앱이 현재 스냅샷과 이전 스냅샷을 직접 비교한다. 서버 최적화가 필요하면 아래 API를 추가할 수 있다.

`GET /v1/analytics/comparison?snapshotId={snapshotId}&baselineSnapshotId={baselineSnapshotId}`

응답 예시:

```json
{
  "currentSnapshotId": "UUID",
  "baselineSnapshotId": "UUID",
  "totalDeltaKRW": 1280000,
  "assetClassDeltas": [
    {
      "assetClass": "domesticStock",
      "currentTotalKRW": 8200000,
      "baselineTotalKRW": 7000000,
      "deltaKRW": 1200000,
      "deltaPercent": 0.1714
    },
    {
      "assetClass": "crypto",
      "currentTotalKRW": 3100000,
      "baselineTotalKRW": 3940000,
      "deltaKRW": -840000,
      "deltaPercent": -0.2132
    }
  ],
  "holdingDeltas": [
    {
      "name": "Apple",
      "assetClass": "foreignStock",
      "currentValueKRW": 7270000,
      "baselineValueKRW": 6920000,
      "deltaKRW": 350000,
      "status": "increased"
    }
  ]
}
```

## 4-2. 자산 비중 조회 (선택 확장)

MVP에서는 앱이 스냅샷의 자산군별 합계를 이용해 원형그래프를 직접 그린다. 서버 계산이 필요하면 아래 API를 추가할 수 있다.

`GET /v1/analytics/allocation?snapshotId={snapshotId}`

응답 예시:

```json
{
  "snapshotId": "UUID",
  "totalKRW": 18420000,
  "slices": [
    {
      "assetClass": "domesticStock",
      "totalKRW": 8200000,
      "percentage": 0.4452
    },
    {
      "assetClass": "crypto",
      "totalKRW": 3100000,
      "percentage": 0.1683
    }
  ]
}
```

## 5. 업로드 세션 생성

`POST /v1/uploads`

요청:

```json
{
  "fileCount": 3,
  "capturedAt": "2026-03-25T10:00:00Z"
}
```

응답:

```json
{
  "uploadSessionId": "UUID",
  "files": [
    {
      "uploadId": "UUID",
      "uploadURL": "http://127.0.0.1:8787/upload-targets/{uploadSessionId}/{uploadId}"
    }
  ]
}
```

업로드는 `PUT {uploadURL}` 로 바이너리 본문을 그대로 전송합니다.

## 6. 분석 시작

`POST /v1/analysis-jobs`

요청:

```json
{
  "uploadSessionId": "UUID"
}
```

응답:

```json
{
  "jobId": "UUID",
  "status": "queued"
}
```

## 7. 분석 상태 조회

`GET /v1/analysis-jobs/{jobId}`

응답:

```json
{
  "jobId": "UUID",
  "status": "completed",
  "snapshotId": "UUID"
}
```

## 현재 로컬 서버 분석 동작

- 업로드가 모두 완료되면 서버가 macOS `Vision` OCR을 수행합니다.
- OCR 결과 텍스트를 바탕으로 자산 행을 추출하고 자산군을 분류합니다.
- 필요한 통화는 KRW 환율을 함께 기록합니다.
- 생성된 스냅샷에는 기록 시점, 자산 목록, 환율, 마지막 동기화 시간이 포함됩니다.

## 히스토리/비교/차트 전략

- 현재 구현 기준 MVP는 `원본 스냅샷 조회 API`만으로 히스토리, 비교, 자산 비중을 앱에서 계산합니다.
- 위의 `analytics/*` 엔드포인트는 기록량 증가 시 선택적으로 추가하는 확장안입니다.
