# MyPort

MyPort는 개인용 iOS 자산 포트폴리오 관리 앱입니다. 은행, 증권사, 코인 거래소 화면을 스크린샷으로 업로드하면 서버가 OCR과 규칙 기반 분석으로 자산을 분류하고, 사용자는 앱에서 검수 후 저장할 수 있습니다.

## 현재 구현된 기능

- 스크린샷 여러 장 업로드
- 서버 OCR 분석 파이프라인
- 자산군 자동 분류
  - 국내주식
  - 해외주식
  - 현금성자산
  - 코인
  - 채권
- 기록 당시 환율 저장
- 총합 원화 계산
- 날짜별 히스토리
- 직전 기록 대비 증감 분석
- 자산 비중 원형그래프
- 분석 결과 검수 및 수정 저장

## 앱 구조

- `MyPortApp`
  - SwiftUI iOS 앱
  - 대시보드, 업로드, 히스토리, 상세, 비교 분석 화면 포함
- `MyPortServer`
  - Node.js 기반 로컬 API 서버
  - 스냅샷 CRUD, 업로드 세션, 분석 작업, OCR 연결
- `DESIGN.md`
  - 상세 제품/아키텍처 설계 문서
- `SERVER_API.md`
  - 서버 API 초안 및 현재 구현 범위

## 실행 방법

### 1. 서버 실행

```bash
cd /Users/changminbyun/codex/MyPort/MyPortServer
npm start
```

서버 기본 주소는 `http://127.0.0.1:8787` 입니다.

### 2. iOS 앱 실행

```bash
cd /Users/changminbyun/codex/MyPort
xcodegen generate
open MyPort.xcodeproj
```

Xcode에서 `MyPortApp` 스킴을 선택한 뒤 시뮬레이터 또는 실기기로 실행합니다.

터미널에서 `xcodebuild`를 직접 쓸 때는 Xcode 경로가 선택되어 있어야 합니다.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project /Users/changminbyun/codex/MyPort/MyPort.xcodeproj \
  -scheme MyPortApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## 업로드 검수 흐름

1. 앱에서 스크린샷 여러 장 선택
2. 서버 업로드 및 분석 시작
3. 분석 완료 후 `검수 및 수정` 시트 자동 오픈
4. 자산/환율/메모 수정
5. 수정 결과를 서버에 저장

## 현재 검증 상태

- iOS 단위 테스트 통과
- 로컬 서버 `PUT /v1/snapshots/{id}` 수정 저장 확인
- 시뮬레이터에서 앱 실행 확인

## 참고 문서

- [설계 문서](./DESIGN.md)
- [서버 API 문서](./SERVER_API.md)
- [서버 README](./MyPortServer/README.md)
