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
| `/kb-strands-agentcore` | Strands Agents + Bedrock AgentCore（エージェント開発、CDK、Observability） |
| `/kb-amplify-cdk` | Amplify Gen2 + CDK（sandbox、本番デプロイ、Hotswap） |
| `/kb-api-patterns` | API設計・SSEストリーミング・外部API連携（モック設計、キャッシュ、Google Sheets連携） |
| `/kb-frontend` | フロントエンド（React、Tailwind、SSE、Amplify UI） |
| `/draw-architecture` | AWSアーキテクチャ図生成（diagramsライブラリ + カスタムアイコン） |
| `/kb-troubleshooting` | トラブルシューティング集（AWS、フロントエンド、Python、LLMアプリ）|
| `/kb-project-authoring` | プロジェクトの学びを再利用可能な `kb-*` スタイルに整理・作成する |
| `/skill-discovery` | 作業完了時に再利用パターンを検知し、`kb-candidate` / `skill-candidate` を提案する |
| `/sync-docs` | 実装とドキュメントの差異を調査し、ドキュメントを実装に合わせて更新する |
| `/sync-knowledge` | プロジェクトで得た学びをグローバルナレッジベースへ反映する |
| `/sync-settings` | Claude Code共通設定（skills/CLAUDE.md/mcpServers）をGitHubリポジトリへ同期する |
| `/backlog-manager` | 「今はやらないが後で検討したい」項目を `BACKLOG.md` に構造化して管理する |

プロジェクト固有でない汎用的な学びを得たら `/sync-knowledge` で追記する。
