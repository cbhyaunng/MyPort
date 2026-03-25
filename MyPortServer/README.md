# MyPort Server

`MyPortApp`의 실서버 모드가 바로 붙을 수 있도록 만든 로컬 JSON 저장 백엔드입니다.

## 실행

```bash
cd /Users/changminbyun/codex/MyPort/MyPortServer
npm start
```

기본 주소는 `http://127.0.0.1:8787` 입니다.

## 환경 변수

- `MYPORT_HOST`
- `MYPORT_PORT`
- `MYPORT_DATA_DIR`
- `MYPORT_PUBLIC_BASE_URL`
- `MYPORT_BEARER_TOKEN`

예시:

```bash
MYPORT_BEARER_TOKEN=dev-token npm start
```

## 포함 기능

- 스냅샷 목록 조회 / 생성 / 삭제
- 업로드 세션 생성
- 업로드 타겟으로 `PUT` 업로드
- 분석 작업 생성 / 상태 조회
- 서버 로컬 디스크에 JSON 데이터 저장
- Apple Vision 기반 OCR
- OCR 텍스트에서 자산 행 추출
- 필요한 통화의 KRW 환율 보강

## 현재 분석 동작

현재 서버는 업로드된 이미지를 macOS `Vision` OCR로 읽고, 텍스트 라인에서 자산을 규칙 기반으로 추출합니다.

- 국내주식, 해외주식, 현금성자산, 코인, 채권을 키워드와 숫자 패턴으로 분류합니다.
- 환율이 화면에서 직접 읽히지 않으면 필요한 통화에 대해 KRW 환율을 조회해 함께 저장합니다.
- 파싱이 애매한 경우에는 스냅샷 메모에 OCR 미리보기를 남깁니다.

이 단계는 아직 범용 금융 화면을 완벽히 이해하는 AI 파서는 아니며, `개인용 MVP` 수준의 OCR + 규칙 엔진입니다.

## iOS 앱 연결

- 시뮬레이터: `http://127.0.0.1:8787`
- 실제 아이폰: 같은 Wi-Fi에서 Mac의 사설 IP 주소를 사용

예: `http://192.168.0.15:8787`
