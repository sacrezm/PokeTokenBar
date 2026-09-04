# PokéForge 기여 안내

[English](CONTRIBUTING.md) · **한국어** · [日本語](CONTRIBUTING.ja.md)

PokéForge는 [chattymin/PokeTokenBar](https://github.com/chattymin/PokeTokenBar)를 바탕으로 독립적으로 유지하는 비상업 팬 프로젝트입니다. 원 프로젝트의 MIT 저작권 고지는 [LICENSE](LICENSE)에 남아 있으며, 기여는 [sacrezm/pokeforge](https://github.com/sacrezm/pokeforge)에서 관리합니다.

## 시작 전

- macOS 14 (Sonoma) 이상
- Swift 6 / Xcode 16 이상 (`swift-tools-version: 6.0`)

공개 제품명은 PokéForge입니다. Swift 제품과 앱 번들은 `PokeForge`를 사용하지만, 호환성을 위해 target/module과 소스 경로는 `PokeTokenBar`, `Sources/PokeTokenBar`로 유지합니다. 내부 이름을 기계적으로 바꾸지 말고 [identity 안내](docs/reference/pokeforge-identity.md)를 먼저 읽어 주세요.

로컬 checkout의 remote는 다음처럼 유지합니다.

```text
origin   https://github.com/sacrezm/pokeforge.git
upstream https://github.com/chattymin/PokeTokenBar.git
```

## 빌드와 테스트

저장소 루트에서 실행합니다.

```bash
swift build
swift test

# build/PokeForge.app 생성, 설치하지 않음
PTB_INSTALL=0 ./scripts/build-app.sh
```

번들 스크립트는 `PokeForge.app`을 만듭니다. `PTB_INSTALL=0`이면 설치하지 않고, 없이 실행하면 실행 중인 앱을 종료한 뒤 `/Applications/PokeForge.app`을 교체합니다. CI는 `swift build`, `scripts/test-gate.sh`의 테스트·커버리지 게이트, secret scan을 실행합니다.

## 기여 흐름

1. `main`에서 범위가 분명한 브랜치를 만듭니다.
2. 문제를 해결하는 최소 변경을 만들고, 동작이 바뀌면 의미 있는 테스트를 추가합니다.
3. `feat:`, `fix:`, `docs:`, `test:`, `refactor:` 같은 Conventional Commit 접두사를 사용합니다.
4. `main`을 대상으로 영문 제목과 본문의 풀 리퀘스트를 엽니다.
5. `Sources/PokeTokenBar/UI/` 아래 UI를 바꾸면 before/after를 설명합니다. 스크린샷은 선택입니다.

공개 기록의 일관성을 위해 풀 리퀘스트와 커밋 메시지는 영어를 우선합니다. 버그에는 macOS 버전, 앱 버전, 영향을 받는 AI 도구, 재현 단계를 적어 주세요.

## 코드 규칙

- **새 사용량 소스:** `Sources/PokeTokenBar/Core/`에 `UsageProvider`를 구현하고 `Sources/PokeTokenBar/Core/UsageStore.swift`의 기본 provider 목록에 등록합니다.
- **범용 사용량 동작:** 모든 provider를 집계합니다. provider별 분기는 해당 provider 고유의 한도나 동작에만 사용합니다.
- **새 도구·버전 매니저 경로:** 탐색과 자식 프로세스 `PATH`가 공유하는 `BinaryLocator.commonToolDirectories()`에 추가합니다.
- **append-only SQLite 사용량:** 워터마크 루프를 복사하지 말고 형식별 query와 parser를 `LocalAdditionalUsageReader.scanIncrementalStores`에 연결합니다.
- **로드맵 구분:** 레벨, XP/EV, 포획·훈련 모드, 트레이너 배틀은 구현·검증되기 전까지 출시 기능과 섞어 쓰지 않습니다.

## 법적·프라이버시 경계

포켓몬이나 제3자 저작물의 에셋을 커밋하거나 번들하지 마세요. 스프라이트·아트워크·오디오·폰트·대량 이름/데이터 파일을 포함합니다. 포켓몬 종 데이터와 스프라이트는 [PokéAPI](https://pokeapi.co/)에서 런타임에 받아 로컬 캐시합니다.

secret, 자격증명, 비공개 툴링 참조, 상업적 사용을 의도한 기능을 커밋하지 마세요. 교환은 선택적 릴레이 기능이며 포켓몬 제안은 클라이언트에서 암호화되지만 트레이너·친구·교환 메타데이터는 선택한 릴레이에 보입니다. 코드와 문서에서 이 경계를 유지하세요.

기여를 제출하면 작업물이 본인의 원본이며 이 프로젝트의 [MIT License](LICENSE)로 배포될 수 있음에 동의하는 것입니다. MIT는 프로젝트 소스 코드에만 적용되며 제3자 포켓몬 지식재산권을 부여하지 않습니다.
