# optiontrade-deploy

123 서버에서 `suaveforge/optiontrade`를 실행하는 전용 배포 저장소(공개). **실제 LS 키·계좌번호·토큰 등 비밀정보는 포함하지 않습니다.**

## 고정 규칙

- 앱 위치 `/home/futures-options-trader/app`; 배포 스크립트 `/home/futures-options-trader/deploy`.
- 원본 단타 프로그램 `/root/stockbroker` 수정·재시작 금지.
- LS **PAPER** 시세 전용. 실전 주문 호출 금지.
- 내부 포트 `127.0.0.1:18765`. 외부 도메인은 HTTPS로 공개하고 별도 로그인·Basic Auth를 요구하지 않습니다. LS 모의투자 데이터만 제공하며 실제 주문은 차단합니다.
- 앱 소스는 비공개 저장소 `suaveforge/optiontrade`에 보관.

## 운영

소스 저장소의 `Deploy optiontrade to server123` Actions에서 공개 배포 저장소의 스크립트를 가져와 실행합니다. 설정·비밀키는 기존 123 서버의 `/home/futures-options-trader/secrets/ls-paper.env` (chmod 600)에만 존재합니다.

## DNS

기본 호스트: `optiontrade.suaveforge.com`. 도메인은 Spaceship의 `suaveforge.com` 존에 A 레코드로 연결하며 **다른 기존 레코드는 변경하지 않습니다.** 외부 접속용 HTTPS는 DNS와 별도 검증합니다. 옵션트레이드 웹 화면은 비밀번호 없이 바로 열립니다.
