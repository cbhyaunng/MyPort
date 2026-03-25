# MyPort Server

`MyPortApp`이 붙는 API 서버입니다. 현재 구조는 `Railway 서비스 + Railway Postgres + Railway Volume + OpenAI 이미지 분석`을 기본 배포 경로로 두고 있고, 로컬 개발에서는 macOS `Vision` OCR fallback을 지원합니다.

## 포함 기능

- 스냅샷 목록 조회 / 생성 / 수정 / 삭제
- 업로드 세션 생성
- 업로드 타겟으로 `PUT` 업로드
- 분석 작업 생성 / 상태 조회
- Postgres 또는 파일 저장 fallback
- 업로드 파일을 볼륨 또는 로컬 디스크에 저장
- OpenAI Responses API 기반 이미지 분석
- macOS Vision OCR fallback
- 필요한 통화의 KRW 환율 보강

## 배포 파일

- [Dockerfile](/Users/changminbyun/codex/MyPort/MyPortServer/Dockerfile)
  - Railway에서 일관된 Node 런타임으로 배포
- [railway.json](/Users/changminbyun/codex/MyPort/MyPortServer/railway.json)
  - Dockerfile 빌드, `/healthz` 헬스체크, 재시작 정책
- [.dockerignore](/Users/changminbyun/codex/MyPort/MyPortServer/.dockerignore)
  - `node_modules`, `data`, `.env` 제외
- [`.env.example`](/Users/changminbyun/codex/MyPort/MyPortServer/.env.example)
  - 로컬/배포 환경 변수 예시

## 로컬 실행

```bash
cd /Users/changminbyun/codex/MyPort/MyPortServer
npm install
MYPORT_ANALYSIS_PROVIDER=vision npm start
```

기본 주소는 `http://127.0.0.1:8787` 입니다.

OpenAI 경로를 로컬에서 테스트하려면:

```bash
cd /Users/changminbyun/codex/MyPort/MyPortServer
OPENAI_API_KEY=your-key MYPORT_ANALYSIS_PROVIDER=openai npm start
```

## 환경 변수

필수 또는 자주 쓰는 값:

- `PORT`
- `MYPORT_HOST`
- `MYPORT_PORT`
- `MYPORT_PUBLIC_BASE_URL`
- `MYPORT_BEARER_TOKEN`
- `MYPORT_ANALYSIS_PROVIDER`
  - `openai`
  - `vision`
- `OPENAI_API_KEY`
- `OPENAI_MODEL`
  - 기본값: `gpt-5.4-mini`
- `OPENAI_REASONING_EFFORT`
  - 기본값: `low`
- `MYPORT_DATABASE_URL`
  - 비우면 파일 저장 fallback 사용
- `DATABASE_URL`
  - Railway Postgres 연결 시 자동 주입 가능
- `MYPORT_DATA_DIR`
  - 업로드 파일 저장 경로
- `RAILWAY_VOLUME_MOUNT_PATH`
  - Railway Volume 마운트 경로
- `MYPORT_SEED_SAMPLE_DATA`
  - 기본값: 로컬 `true`, Railway `false`

샘플은 [`.env.example`](/Users/changminbyun/codex/MyPort/MyPortServer/.env.example)에 있습니다.

## Railway 배포 권장값

Railway 서비스 소스는 `MyPortServer` 디렉터리로 잡는 것이 가장 단순합니다.

추가할 서비스:

1. `MyPortServer` 웹 서비스
2. `PostgreSQL`
3. `Volume`

권장 환경 변수:

```bash
MYPORT_ANALYSIS_PROVIDER=openai
MYPORT_BEARER_TOKEN=your-strong-token
MYPORT_SEED_SAMPLE_DATA=false
OPENAI_API_KEY=your-openai-key
OPENAI_MODEL=gpt-5.4-mini
MYPORT_DATA_DIR=/data/myport
```

설명:

- Railway는 서비스에 `RAILWAY_PUBLIC_DOMAIN`, `RAILWAY_VOLUME_MOUNT_PATH` 같은 시스템 변수를 제공합니다.
- Postgres 서비스는 `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`, `DATABASE_URL`을 제공합니다.
- 이 서버는 `MYPORT_DATABASE_URL`이 없으면 `DATABASE_URL`을 자동으로 사용합니다.
- 볼륨이 붙어 있으면 `MYPORT_DATA_DIR`를 예를 들어 `/data/myport` 같은 경로로 지정하는 것이 안전합니다.

### Railway 대시보드 배포 순서

1. Railway에서 새 프로젝트 생성
2. `Deploy from GitHub repo` 선택
3. 저장소 `cbhyaunng/MyPort` 연결
4. 서비스 Root Directory를 `MyPortServer`로 지정
5. Postgres 추가
6. Volume 추가
7. 환경 변수 입력
8. 재배포 후 `/healthz` 확인

### Railway CLI 배포 순서

```bash
cd /Users/changminbyun/codex/MyPort/MyPortServer
npx @railway/cli@latest login
npx @railway/cli@latest link
npx @railway/cli@latest up
```

CLI에서 `link` 또는 `up` 시 서비스 타겟을 물으면 `MyPortServer` 서비스를 선택하면 됩니다.

## 현재 분석 동작

### Railway / 클라우드

- OpenAI Responses API로 여러 장의 스크린샷을 한 번에 보냅니다.
- 이미지 입력을 사용해 구조화 JSON을 직접 받습니다.
- 받은 자산 목록을 서버 쪽 규칙으로 한 번 더 정리하고 중복 제거합니다.
- 화면에 환율이 있으면 그 값을 우선 저장하고, 없으면 필요한 통화의 KRW 환율을 조회해 채웁니다.

### 로컬 macOS fallback

- macOS `Vision` OCR로 텍스트 줄을 추출합니다.
- 기존 규칙 엔진으로 종목명, 수량, 평가금액, 통화, 자산군을 추론합니다.

## 저장 구조

- 메타데이터
  - 권장: Railway Postgres
  - fallback: 로컬 JSON 파일
- 업로드 이미지
  - 권장: Railway Volume
  - fallback: 로컬 디스크

이 구조는 개인용 장기 운영 기준으로 `메타데이터는 DB`, `이미지는 볼륨`에 두는 쪽에 맞춰져 있습니다.

## 상태 확인

`GET /healthz`

응답에는 다음이 포함됩니다.

- `mode`
  - `postgres` 또는 `file-json`
- `analysisProvider`
  - `openai` 또는 `vision`
- `analysisModel`
- `openAIConfigured`
- `databaseConfigured`

## iOS 앱 연결

- 시뮬레이터: `http://127.0.0.1:8787`
- 실제 아이폰: 같은 Wi-Fi에서 Mac의 사설 IP 주소를 사용
- Railway 배포 후: `https://<railway-domain>`

예: `https://myport-api.up.railway.app`
