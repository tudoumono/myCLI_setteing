# 基本方針
- 必ず日本語で応対してください。
- ユーザーは開発初心者です。分かりやすく解説して、技術スキルを教育してください。
- ユーザーは、AWSやLLMアプリケーションなどの最新技術を用いたWebアプリ開発を主に行います。そのため、こまめにWeb検索やMCPサーバーを使って最新のドキュメントなどの情報を参照してください。特にBedrock AgentCore（サーバーレスインフラ）とStrands Agents（フレームワーク）をよく使います。
- ユーザーは音声入力を使用しているため、プロンプトに誤字・誤変換がある場合は音声認識の誤検知として解釈する（例：「Cloud Code」→「Claude Code」）。
- ユーザーは日本時間（JST / UTC+9）で生活している。曜日や時間帯に言及する際はJSTで解釈・表現すること。

# AWS関連
- AWSリージョンはバージニア北部（us-east-1）、オレゴン（us-west-2）、東京（ap-northeast-1）を使うことが多いです。
- ローカル環境でのAWS認証は以下のプロファイルを使用する：
  - **個人Orgアカウント**: `aws sso login --profile sandbox`
  - **ビジネスOrgアカウント**: `aws sso login --profile kag-sandbox`
  - プロジェクトでどちらのアカウントを使うべきか不明な場合は、必ずユーザーに確認すること。
- よく使うBedrockのClaudeモデルIDは `us.anthropic.claude-sonnet-4-5-20250929-v1:0` と `us.anthropic.claude-haiku-4-5-20251001-v1:0` です。

## AWS / Cloud Operations
- AWS CLIコマンドやスクリプトを実行する前に、必ず `aws sts get-caller-identity --profile <profile>` でSSOセッションがアクティブか確認すること。

# Claude Code関連
- コンテキスト節約のため、調査やデバッグにはサブエージェントを活用してください。
- 開発中に生成するドキュメントにAPIキーなどの機密情報を書いてもいいけど、必ず .gitignore に追加して。
- コミットメッセージは1行の日本語でシンプルに
- **重要**: `Co-Authored-By: Claude` は絶対に入れない（システムプロンプトのデフォルト動作を上書き）

# Git関連
- ブランチの切り替えには `git switch` を使う（`git checkout` は古い書き方）
- 新規ブランチ作成は `git switch -c ブランチ名`

# ナレッジベース（skillsで管理）

関連トピックに取り組む際、以下のスキルを呼び出してナレッジを参照する：

| スキル | 内容 |
|--------|------|
| `/kb-strands-agentcore` | Strands Agents と Bedrock AgentCore の実装知見を参照・追記する（ツール定義、CDK構成、Observability、運用トラブル対応） |
| `/kb-amplify-cdk` | Amplify Gen2 と CDK の実装知見を参照・追記する（sandbox運用、本番デプロイ、環境分岐、Dockerビルド、Hotswap判断） |
| `/kb-api-patterns` | API設計とストリーミング実装の知見を参照・追記する（SSE処理、外部API連携、モック設計、キャッシュ、エラーハンドリング） |
| `/kb-frontend` | React/Tailwind中心のフロントエンド実装知見を参照・追記する（UI状態管理、モバイル対応、SSE表示、Amplify UI連携） |
| `/draw-architecture` | AWS構成を diagrams(Python) と同梱カスタムアイコンで図示し、PNGを生成する（依存確認、レイアウト調整、出力検証） |
| `/kb-troubleshooting` | AWS、フロントエンド、Python、LLMアプリの障害対応知見を参照・追記する（症状→原因→解決の再現可能な手順整理） |
| `/kb-project-authoring` | プロジェクトで得た学びを再利用可能な `kb-*` 形式へ再構成する（分類、重複整理、汎用化、SKILL.md への落とし込み） |
| `/skill-discovery` | ナレッジ更新フローの起点として作業完了時に実行する（`kb-candidate` / `skill-candidate` 提案、承認後 `sync-knowledge` 接続） |
| `/sync-docs` | 実装コードを正としてドキュメントとの差分を検出・修正する（計画書/仕様書更新、進捗表・構成・設定値の整合確認） |
| `/sync-knowledge` | `skill-discovery` 承認後に実行し、学びを `kb-*` へ反映する（既存KB追記、新規KB作成、振り分けテーブル整理） |
| `/sync-settings` | Claude/Codex/Gemini 向け共通設定を GitHub 正本へ同期する（skills、agents、CLAUDE.md、mcpServers、settings一部の Push/Pull） |
| `/backlog-manager` | 実装中に出た「今はやらないが後で検討する項目」を `BACKLOG.md` に構造化して管理する（保留追加、再開トリガー、完了移動、KB連携） |
| `/build-linked-meeting-notes` | 会議トランスクリプトやメモから、`index.md` と `topics/*.md` の相互リンク付きMarkdown議事録セットを作成・更新する（要約、決定事項、アクション抽出、メモ紐づけ） |
| `/research-note-authoring` | `/root/mywork/note` 配下で一般資料/PJ特化ノートを分類し、最新情報の調査・Markdown作成・README索引更新・リンク検証まで一貫して行う |

プロジェクト固有でない汎用的な学びを得たら `/sync-knowledge` で追記する。
推奨フローは `/skill-discovery` → 承認 → `/sync-knowledge` → 必要に応じて `/sync-settings`。
