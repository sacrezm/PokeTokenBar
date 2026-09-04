# PokéForge

**AI 코딩을 포켓몬의 성장으로 바꿔 보세요.**

이미 사용하고 있는 코딩 도구의 토큰을 읽어 macOS 메뉴바의 동료 포켓몬을 키우고, 작업하는 동안 컬렉션을 채웁니다.

[영문 README (기준 문서)](README.md) · [릴리스](https://github.com/sacrezm/pokeforge/releases) · [소스](https://github.com/sacrezm/pokeforge) · [기여 안내](CONTRIBUTING.ko.md)

> **포크 출처:** PokéForge는 [chattymin/PokeTokenBar](https://github.com/chattymin/PokeTokenBar)의 독립 유지 포크입니다. 원 프로젝트의 MIT 저작권 고지는 [LICENSE](LICENSE)에 남아 있으며, 이 포크의 저장소는 [sacrezm/pokeforge](https://github.com/sacrezm/pokeforge)입니다.

## 현재 제공

- **사용량 추적:** Claude Code, Codex, Gemini CLI, Antigravity, OpenCode, Hermes Agent, Cursor, Grok CLI, Copilot CLI, Kiro CLI, Pi Agent, omp의 로컬 사용량 기록을 읽습니다. 오늘·주·월 합계와 지원되는 공식 한도를 보여 줍니다.
- **부화와 진화:** 코딩 사용량으로 알을 부화하고 실제 진화 계보를 따라 동료를 키운 뒤, 완성한 포켓몬을 컬렉션에 졸업시킵니다. 부화에는 희귀도·성격·이로치가 적용됩니다.
- **상점:** 사용한 토큰을 이상한 사탕, 민트, 이로치 부적, 새 알 또는 고급·희귀 보증 알로 바꿉니다.
- **컬렉션:** 현재 보유 포켓몬, 종 단위 도감, 개체별 포획 로그를 확인합니다. 플로팅 펫과 메뉴바 대표 포켓몬도 선택할 수 있습니다.
- **교환:** 트레이너를 만들고 친구 코드로 친구를 추가한 뒤 공유 릴레이를 통해 완성한 포켓몬 한 마리를 교환합니다. 양쪽이 확인하며 원래 트레이너 정보가 보존됩니다. 알과 현재 키우는 동료는 교환할 수 없습니다.

## 개발 중인 방향

포켓몬 레벨, XP·EV, 포획 모드와 훈련 모드, 장래의 트레이너 배틀을 개발 중입니다. **로드맵 항목이며 현재 빌드에는 어느 것도 제공되지 않습니다.** 현재 게임 루프는 토큰 기반 부화·진화·사용량 추적·상점·컬렉션·선택적 교환입니다.

## 스크린샷

아래 이미지는 PokéForge로 공개 리브랜딩하기 전의 출시 UI입니다. 일부 표시는 원래 이름을 사용합니다.

<p align="center">
  <img src="assets/screenshot-home.gif" width="360" alt="리브랜딩 전 홈 화면 — 동료와 사용량 합계">
</p>

<p align="center">
  <img src="assets/screenshot-shop-ko.png" width="250" alt="리브랜딩 전 상점 화면">
  <img src="assets/screenshot-collection-pokedex.png" width="250" alt="리브랜딩 전 도감 화면">
</p>

## 설치와 전환

[PokéForge 릴리스](https://github.com/sacrezm/pokeforge/releases)에서 앱 ZIP을 내려받으세요. GitHub가 자동으로 만드는 소스 코드 ZIP이 아니라 빌드된 앱 ZIP을 사용하고, 압축을 푼 앱을 `/Applications`로 옮깁니다.

이름 변경 작업에서는 새 바이너리를 공개하지 않습니다. 현재 최신 다운로드는 `PokeTokenBar-v2.6.3.zip`이며 안에 `PokeTokenBar.app`이 들어 있습니다. 첫 브랜드 릴리스부터는 `PokeForge-vX.Y.Z.zip`과 `PokeForge.app`을 사용합니다.

v2.6.3을 포함한 모든 PokéForge 이전 빌드는 예전 `sacrezm/PokeTokenBar`의 정확한 `html_url`만 허용합니다. GitHub 이름 변경의 리디렉션은 새 canonical URL을 돌려주므로, 이전 빌드는 릴리스를 찾지 못합니다. **첫 PokéForge 릴리스는 한 번 수동으로 설치해야 합니다.**

1. 기존 PokeTokenBar에서 **로그인 시 실행**을 끕니다.
2. PokeTokenBar를 정상적으로 종료합니다.
3. 첫 `PokeForge-vX.Y.Z.zip`을 내려받아 `PokeForge.app`을 `/Applications`에 넣고 엽니다.
4. 컬렉션·트레이너 프로필·설정을 확인한 뒤 새 앱에서 **로그인 시 실행**을 다시 켭니다.
5. 확인이 끝난 뒤 기존 앱을 제거합니다. Application Support, 설정, Keychain 데이터를 지우는 앱 클리너는 사용하지 마세요.

전체 호환성은 [identity 및 전환 안내](docs/reference/pokeforge-identity.md)와 [영문 README](README.md)를 참고하세요.

## 소스 빌드

macOS 14 이상, Swift 6 / Xcode 16이 필요합니다.

```bash
swift build
swift test

# build/PokeForge.app 생성, 설치하지 않음
PTB_INSTALL=0 ./scripts/build-app.sh

# build/PokeForge.app 생성 후 /Applications에 설치
./scripts/build-app.sh
```

`PTB_INSTALL=0`은 `build/PokeForge.app`만 만들고 설치하지 않습니다. 인자 없이 실행하면 실행 중인 PokéForge를 종료한 뒤 `/Applications/PokeForge.app`을 교체합니다.

## 호환성 이름

공개 제품명은 PokéForge지만, 기존 데이터와 자격증명을 위해 다음 이름은 유지됩니다.

- Swift 제품은 `PokeForge`이고, Swift target/module과 소스 경로는 `PokeTokenBar`, `Sources/PokeTokenBar`입니다.
- Pokémon, 교환 상태, 캐시는 `~/Library/Application Support/PokeTokenBar/`에 남습니다.
- 기존 Keychain 서비스와 bundle identifier `io.github.chattymin.poketokenbar`를 유지합니다.

## 프라이버시와 교환

사용량 집계는 AI 도구의 로컬 로그·데이터베이스를 읽습니다. 사용량 로그, 프롬프트, 프로젝트 경로를 교환 릴레이로 보내지 않습니다. 공식 한도·계정 사용량과 업데이트 확인에는 일부 네트워크 요청이 필요합니다.

포켓몬 종·진화 데이터와 스프라이트는 런타임에 받아 로컬 캐시하며, 앱과 릴리스 ZIP에 포켓몬 에셋을 번들하지 않습니다.

교환은 선택 기능이며 릴레이를 사용합니다. 릴레이에는 트레이너 프로필, 친구 코드, 공개 키, 친구 관계와 교환 메타데이터가 전달됩니다. 포켓몬 제안 내용은 이 Mac에서 암호화되지만 릴레이가 보는 메타데이터는 보관될 수 있습니다. 교환 개인 키와 bearer 자격증명은 macOS Keychain에 남습니다. 신뢰하는 릴레이만 사용하세요.

## 라이선스와 면책

[MIT License](LICENSE)는 프로젝트 소스 코드에 적용되며 원 프로젝트의 `chattymin` 저작권 고지를 유지합니다. Pokémon 상표·아트워크·스프라이트·데이터에 대한 권리를 부여하지 않습니다.

PokéForge는 비공식·비상업 팬 프로젝트이며 Nintendo, Game Freak, Creatures Inc., The Pokémon Company와 제휴·보증·후원·승인 관계가 없습니다. 포켓몬 데이터와 스프라이트는 [PokéAPI](https://pokeapi.co/)에서 런타임에 가져오며 각 권리자에게 속합니다.

기여 전에는 [CONTRIBUTING.ko.md](CONTRIBUTING.ko.md)를 읽어 주세요.
