# No Focus Count

공부할 창과 모니터를 정하고 뽀모도로를 시작하면, 집중 맥락에서 벗어난 시간과 횟수를 자동으로 기록하는 로컬 우선 집중 타이머입니다. macOS, Windows, Linux용 투명 데스크톱 앱과 macOS 네이티브 실험판을 함께 제공합니다.

## Cross-platform desktop v0.3

Electron 앱은 [`cross-platform`](cross-platform)에 있습니다.

- 집중/짧은 휴식/긴 휴식과 일일 목표
- 선택한 모니터를 벗어나거나 다른 창을 활성화하면 자동 정지
- 같은 브라우저 창에서 다른 탭으로 바뀌어도 자동 정지
- 화면 잠금, 절전, 시스템 유휴 상태에서도 자동 정지
- 포커스를 빼앗지 않고 항상 위에 표시되는 투명 숫자 오버레이
- 숫자·포인트·패널 색, 투명도, 블러, 크기, 글로우 테마 설정
- 세션별 집중/이탈 시간, 이탈 원인, 앱, 창 제목과 동의한 URL 기록
- 월별 집중 시간 달력, 일일 목표 히트맵, 집중왕·딴짓왕 요약
- 완료 알람과 JSON 가져오기/내보내기
- 선택형 self-hosted 계정 연동 서버
- 낮은 해상도에서는 앱 내부가 스크롤되고 타이머가 자동 축소되는 반응형 UI

기본 상태에서는 키 입력, 페이지 본문, 화면 영상, SNS 내용을 수집하지 않습니다. URL 저장도 사용자가 직접 켜야 합니다. 기록은 먼저 각 기기의 앱 데이터 폴더에 저장됩니다.

### 실행과 개발

Node.js 24 이상을 권장합니다.

```bash
cd cross-platform
npm ci
npm start
```

검증과 현재 운영체제용 설치 파일 생성:

```bash
npm test
npm audit --audit-level=high
npm run dist
```

GitHub Actions가 태그 릴리스마다 macOS의 DMG/ZIP, Windows의 설치 EXE/portable EXE, Linux의 AppImage/DEB를 각 운영체제에서 빌드합니다. 서명되지 않은 개발 릴리스라 운영체제가 최초 실행 때 경고를 표시할 수 있습니다.

### 집중 판정

집중 세션은 서로 보완하는 신호를 사용합니다.

1. 활성 창 중심점이 선택한 모니터 안에 있는지 확인합니다.
2. 선택한 창과 현재 활성 창을 비교합니다.
3. URL을 제공하는 브라우저에서는 시작 탭과 현재 탭을 비교하고, URL이 없으면 창 제목 변경을 보조 신호로 사용합니다.
4. 화면 잠금·절전 이벤트와 설정한 시스템 유휴 시간을 확인합니다.

앱을 조작하는 동안에는 사용자가 설정을 바꿀 수 있도록 집중 이탈로 처리하지 않습니다. Linux Wayland는 다른 앱의 활성 창 정보를 제한하므로 커서가 위치한 모니터를 기준으로만 판정합니다. Linux에서 창과 탭까지 감지하려면 X11 세션을 사용하세요.

### 선택형 기기 연동

[`cross-platform/sync-server`](cross-platform/sync-server)의 작은 Node.js 서버를 직접 배포할 수 있습니다.

```bash
cd cross-platform/sync-server
NFC_SYNC_TOKEN='긴-랜덤-토큰' PORT=8787 npm start
```

HTTPS 리버스 프록시 뒤에서 실행한 다음 앱의 **기기 연동**에 서버 주소, 계정 ID, 토큰을 넣습니다. 세션은 ID 기준으로 병합되며 토큰은 운영체제의 안전 저장소를 사용할 수 있을 때 암호화해 보관합니다. 이 저장소는 동기화 서버를 자동 호스팅하지 않습니다.

## macOS native prototype

루트의 SwiftUI 앱은 창 노출 비율과 선택형 저해상도 Focus Receipt를 실험하는 macOS 14+ 네이티브 구현입니다.

```bash
sh Scripts/build-app.sh
open dist/NoFocusCount.app
```

처음 실행할 때 **시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용** 권한이 필요합니다. URL 기록은 브라우저 자동화 권한, Focus Receipt는 화면 및 시스템 오디오 기록 권한을 추가로 요청할 수 있습니다. Focus Receipt는 기본적으로 꺼져 있고, 켠 경우에도 이탈이 2초 이상 이어진 시점의 해당 창 한 장만 480px JPEG로 로컬 저장합니다.

## 테스트

```bash
# Cross-platform 핵심 정책
cd cross-platform && npm test

# macOS Swift 구현
swift test
sh Scripts/test-core.sh
sh Scripts/build-app.sh
```

CI는 두 구현의 핵심 테스트와 macOS 앱 빌드를 검사합니다. 데스크톱 릴리스 워크플로는 macOS, Windows, Linux 패키지를 별도 러너에서 생성합니다.

## 알려진 제한

- 운영체제와 브라우저가 URL을 제공하지 않으면 탭 변경은 창 제목을 이용한 보조 판정이며 완벽하지 않을 수 있습니다.
- DRM, 보안 창, 일부 전체화면 앱은 활성 창 메타데이터를 숨길 수 있습니다.
- 현재 공개 릴리스는 코드 서명과 macOS 공증을 하지 않은 개발 배포판입니다.
- 계정 연동은 사용자가 서버를 직접 운영해야 하며 기본값은 로컬 전용입니다.
