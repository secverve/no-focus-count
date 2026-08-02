# No Focus Count Sync Server

선택 기능인 기기 간 기록 연동을 위한 최소 self-hosted 서버입니다. Node.js 20 이상에서 외부 패키지 없이 실행됩니다.

```bash
NFC_SYNC_TOKEN='긴-랜덤-토큰' PORT=8787 npm start
```

앱의 **기기 연동**에서 서버 주소, 동일한 계정 ID, 동일한 토큰을 입력하면 여러 기기의 세션을 ID 기준으로 병합합니다. HTTPS 리버스 프록시 뒤에서 실행하고 토큰을 타인과 공유하지 마세요.

데이터는 기본적으로 `./data`에 저장됩니다. `NFC_SYNC_DATA_DIR`로 다른 절대 경로를 지정할 수 있습니다.
