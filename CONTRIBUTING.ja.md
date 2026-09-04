# PokéForge への貢献

[English](CONTRIBUTING.md) · [한국어](CONTRIBUTING.ko.md) · **日本語**

PokéForge は [chattymin/PokeTokenBar](https://github.com/chattymin/PokeTokenBar) を基に独立して管理する非商用ファンプロジェクトです。元プロジェクトの MIT 著作権表示は [LICENSE](LICENSE) に残り、貢献は [sacrezm/pokeforge](https://github.com/sacrezm/pokeforge) で管理されます。

## 始める前に

- macOS 14 (Sonoma) 以降
- Swift 6 / Xcode 16 以降（`swift-tools-version: 6.0`）

公開製品名は PokéForge です。Swift 製品とアプリバンドルは `PokeForge` を使いますが、互換性のため target/module とソースパスは `PokeTokenBar`、`Sources/PokeTokenBar` のままです。内部名を機械的に変更せず、[identity のメモ](docs/reference/pokeforge-identity.md)を確認してください。

ローカル checkout の remote は次のようにします。

```text
origin   https://github.com/sacrezm/pokeforge.git
upstream https://github.com/chattymin/PokeTokenBar.git
```

## ビルドとテスト

リポジトリのルートから実行します。

```bash
swift build
swift test

# build/PokeForge.app を作成し、インストールしない
PTB_INSTALL=0 ./scripts/build-app.sh
```

バンドルスクリプトは `PokeForge.app` を作成します。`PTB_INSTALL=0` ならインストールせず、指定しない場合は起動中のアプリを終了して `/Applications/PokeForge.app` を置き換えます。CI は `swift build`、`scripts/test-gate.sh` のテスト・カバレッジゲート、secret scan を実行します。

## 貢献の流れ

1. `main` から範囲を絞ったブランチを作成します。
2. 問題を解決する最小の変更を行い、動作が変わる場合は意味のあるテストを追加します。
3. `feat:`, `fix:`, `docs:`, `test:`, `refactor:` などの Conventional Commit 接頭辞を使います。
4. `main` に向けて、英語のタイトルと本文でプルリクエストを開きます。
5. `Sources/PokeTokenBar/UI/` 配下を変更した場合は before/after を説明します。スクリーンショットは任意です。

公開履歴を一貫させるため、プルリクエストとコミットメッセージは英語を第一言語にします。バグには macOS のバージョン、アプリのバージョン、影響する AI ツール、再現手順を含めてください。

## コード規約

- **新しい使用量ソース:** `Sources/PokeTokenBar/Core/` に `UsageProvider` を実装し、`Sources/PokeTokenBar/Core/UsageStore.swift` のデフォルト一覧に登録します。
- **汎用の使用量動作:** すべての provider を集計します。provider 固有の分岐は、その provider 固有の上限や動作だけに使います。
- **新しいツール・バージョンマネージャーのパス:** 探索と子プロセスの `PATH` が共有する `BinaryLocator.commonToolDirectories()` に追加します。
- **追記専用 SQLite 使用量:** watermark ループを複製せず、形式ごとの query と parser を `LocalAdditionalUsageReader.scanIncrementalStores` に接続します。
- **ロードマップの区別:** レベル、XP/EV、捕獲・トレーニングモード、トレーナーバトルは実装・検証されるまでリリース済み機能として扱いません。

## 法務とプライバシーの境界

ポケモンや第三者の著作物のアセットをコミット・バンドルしないでください。スプライト、アートワーク、音声、フォント、大量の名前・データファイルを含みます。ポケモンの種データとスプライトは [PokéAPI](https://pokeapi.co/) から実行時に取得し、ローカルにキャッシュします。

シークレット、認証情報、非公開ツールへの参照、商用利用を意図した機能をコミットしないでください。交換は任意のリレー機能です。ポケモンのオファーはクライアントで暗号化されますが、トレーナー・フレンド・交換のメタデータは選択したリレーから見えます。この境界をコードとドキュメントで保ってください。

貢献を提出することで、あなたの作業がオリジナルであり、本プロジェクトの [MIT License](LICENSE) の下で配布できることに同意したものとします。MIT は本プロジェクトのソースコードのみを対象とし、第三者のポケモン知的財産権を付与しません。
