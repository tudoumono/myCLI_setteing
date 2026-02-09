---
name: kb-api-patterns
description: API設計とストリーミング実装の知見を参照・追記する。SSE処理、外部API連携、モック設計、キャッシュ、エラーハンドリングに使う
user-invocable: true
---

# API・ストリーミングパターン

SSE処理、API設計、外部API連携など、フロントエンド/バックエンド横断のパターンを記録する。

> **関連スキル**: UIパターンは `/kb-frontend`、トラブルシューティングは `/kb-troubleshooting` を参照。

## 目次

- [SSEストリーミング処理](#sseストリーミング処理)
- [環境変数の読み込み](#環境変数の読み込み)
- [API設計パターン](#api設計パターン)
- [外部API連携パターン](#外部api連携パターン)

---

## SSEストリーミング処理

### 基本パターン
```typescript
const reader = response.body?.getReader();
const decoder = new TextDecoder();
let buffer = '';

while (true) {
  const { done, value } = await reader.read();
  if (done) break;

  buffer += decoder.decode(value, { stream: true });
  const lines = buffer.split('\n');
  buffer = lines.pop() || '';  // 不完全な行は次回に持ち越し

  for (const line of lines) {
    if (line.startsWith('data: ')) {
      const data = line.slice(6);
      if (data === '[DONE]') return;
      try {
        const event = JSON.parse(data);
        handleEvent(event);
      } catch {
        // JSONパースエラーは無視
      }
    }
  }
}
```

### イベントハンドリング
```typescript
function handleEvent(event) {
  // APIによってcontent/dataのどちらかにペイロードが入る
  const textValue = event.content || event.data;

  switch (event.type) {
    case 'text':
      onText(textValue);
      break;
    case 'tool_use':
      onToolUse(textValue);  // ツール名が返る
      break;
    case 'markdown':
      onMarkdown(textValue);
      break;
    case 'error':
      onError(new Error(event.error || event.message || textValue));
      break;
  }
}
```

### エラーハンドリング
```typescript
// ストリーミング中のエラー
case 'error':
  if (event.error || event.message) {
    callbacks.onError(new Error(event.error || event.message));
  }
  break;

// HTTPエラー
const response = await fetch(url, options);
if (!response.ok) {
  throw new Error(`API Error: ${response.status} ${response.statusText}`);
}
```

### アイドルタイムアウト（2段構成）

SSEストリームに2段階のタイムアウトを設定し、接続障害と推論ハングの両方を検知するパターン：

```typescript
async function readSSEStream(
  reader: ReadableStreamDefaultReader<Uint8Array>,
  onEvent: (event: Record<string, unknown>) => void,
  idleTimeoutMs?: number,          // 初回イベント受信前（短め: 10秒）
  ongoingIdleTimeoutMs?: number    // イベント間（長め: 60秒）
): Promise<void> {
  let firstEventReceived = false;

  while (true) {
    // フェーズに応じてタイムアウト値を切り替え
    const currentTimeout = firstEventReceived ? ongoingIdleTimeoutMs : idleTimeoutMs;
    if (currentTimeout) {
      const timeoutPromise = new Promise<never>((_, reject) => {
        setTimeout(() => reject(new SSEIdleTimeoutError(currentTimeout)), currentTimeout);
      });
      readResult = await Promise.race([reader.read(), timeoutPromise]);
    } else {
      readResult = await reader.read();
    }
    // ... イベント処理後に firstEventReceived = true
  }
}
```

| フェーズ | タイムアウト | 検知対象 |
|---------|------------|---------|
| 初回イベント受信前 | 短め（10秒） | スロットリング、接続エラー |
| イベント間（初回受信後） | 長め（60秒） | 推論ハング、モデル無応答 |

**設計ポイント**:
- 初回タイムアウトは短く → ユーザーを素早くエラーに気づかせる
- イベント間タイムアウトは長めに → 正常な推論やツール実行を妨げない
- 通常のストリーミングではチャンクが頻繁に来るため、60秒無音は異常と判断できる

### モック実装（ローカル開発用）

```typescript
export async function invokeAgentMock(prompt, callbacks) {
  const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

  // 思考過程をストリーミング
  const thinkingText = `${prompt}について考えています...`;
  for (const char of thinkingText) {
    callbacks.onText(char);
    await sleep(20);
  }

  callbacks.onStatus('生成中...');
  await sleep(1000);

  callbacks.onMarkdown('# 生成結果\n\n...');
  callbacks.onComplete();
}

// 環境変数で切り替え
const useMock = import.meta.env.VITE_USE_MOCK === 'true';
const invoke = useMock ? invokeAgentMock : invokeAgent;
```

### PDF生成（Base64デコード・ダウンロード）

```typescript
export async function exportPdf(markdown: string): Promise<Blob> {
  const response = await fetch(url, {
    method: 'POST',
    headers: { /* 認証ヘッダー等 */ },
    body: JSON.stringify({ action: 'export_pdf', markdown }),
  });

  const reader = response.body?.getReader();
  const decoder = new TextDecoder();
  let buffer = '';

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop() || '';

    for (const line of lines) {
      if (line.startsWith('data: ')) {
        const event = JSON.parse(line.slice(6));
        if (event.type === 'pdf' && event.data) {
          // Base64デコードしてBlobを返す
          const binaryString = atob(event.data);
          const bytes = new Uint8Array(binaryString.length);
          for (let i = 0; i < binaryString.length; i++) {
            bytes[i] = binaryString.charCodeAt(i);
          }
          return new Blob([bytes], { type: 'application/pdf' });
        }
      }
    }
  }
  throw new Error('PDF生成に失敗しました');
}

// ダウンロード処理
const blob = await exportPdf(markdown);
const url = URL.createObjectURL(blob);
const a = document.createElement('a');
a.href = url;
a.download = 'slide.pdf';
a.click();
URL.revokeObjectURL(url);
```

---

## 環境変数の読み込み（.env vs .env.local）

| フレームワーク/ツール | .env | .env.local | 備考 |
|-----------|------|-----------|------|
| Vite | ○ | ○ | 両方読む（優先度: .env.local > .env） |
| Next.js | ○ | ○ | 両方読む |
| **Node.js dotenv** | ○ | × | `.env` のみ |

Amplify CDK（`import 'dotenv/config'`）とViteの両方で使う場合は **`.env`** に統一する。

---

## API設計パターン

### モックフォールバック付きAPI Route

環境変数未設定時にモックデータを返すパターン（開発・デモ・デプロイ初期に便利）:

```typescript
// src/app/api/data/route.ts (Next.js Route Handler)
import { mockData } from "@/data/mockData";

export async function GET() {
  const isMockMode =
    !process.env.EXTERNAL_API_KEY ||
    process.env.EXTERNAL_API_KEY === "your_key_here";

  if (isMockMode) {
    return Response.json(mockData);
  }

  // 実API呼び出し
  const data = await fetchFromExternalAPI();
  return Response.json(data);
}
```

**メリット**:
- env未設定でもビルド・デプロイが成功する
- デモ環境をすぐに公開できる
- 段階的に実データに切り替え可能

### 動的importで未設定時のモジュールエラー回避

外部APIクライアント（Google Sheets, Firebase等）が環境変数未設定時にモジュール読み込みエラーを起こす場合、動的importで回避:

```typescript
// src/app/api/data/route.ts
import { mockData } from "@/data/mockData";
import { isMockMode } from "@/lib/config";

export async function GET() {
  if (isMockMode()) {
    return Response.json({ data: mockData, source: "mock" });
  }

  // 動的import → env未設定時にモジュール読み込みエラーが起きない
  const { getClient, getResourceId } = await import("@/lib/external-api/client");
  const { parseResponse } = await import("@/lib/external-api/parser");

  const client = getClient();
  const response = await client.getData({ resourceId: getResourceId() });
  const data = parseResponse(response);

  return Response.json({ data, source: "api" });
}
```

**ポイント**:
- 静的 `import` だとモジュール評価時に `process.env.API_KEY` が `undefined` でエラー
- `await import()` は実行時にのみ評価されるため、モック分岐の先に置ける
- レスポンスに `source` フィールドを含めると、モック/実データの切り分けがUI側で可能

### APIレスポンスのエンベロープ形式

全APIで統一的なレスポンス形式を使うと、クライアント側のハンドリングが簡単になる:

```typescript
type ApiResponse<T> = {
  data: T;
  source: "mock" | "api";
  error?: string;
};
```

- `source` でデータソースを識別（UI上にデータソース表示が可能）
- `error` はオプショナル。エラー時でも `data` は空配列等を返す（クライアント側のnullチェック不要）

### サーバーサイドキャッシュ（TTL付き）

API Routeでの外部API呼び出しにメモリキャッシュを設ける:

```typescript
let cache: { data: MyData[]; fetchedAt: number } | null = null;
const CACHE_TTL = 5 * 60 * 1000; // 5分

export async function GET(request: NextRequest) {
  const refresh = request.nextUrl.searchParams.get("refresh") === "true";
  const now = Date.now();

  if (!cache || refresh || now - cache.fetchedAt > CACHE_TTL) {
    const data = await fetchFromExternalAPI();
    cache = { data, fetchedAt: now };
  }

  return Response.json({ data: cache.data, source: "api" });
}
```

**ポイント**:
- `refresh=true` クエリパラメータで強制再取得
- TTL内はメモリキャッシュから即座に返却
- Serverless環境（Lambda）ではコールドスタートでキャッシュがリセットされる点に注意

---

## 外部API連携パターン

### Google Sheets API 連携

サービスアカウント認証 + googleapis クライアントのシングルトンパターン:

```typescript
// lib/external-api/config.ts
const PLACEHOLDER_ID = "your_resource_id_here";

export function resolveResourceIdFromEnv(): string | null {
  const id = process.env["RESOURCE_ID"]?.trim();
  if (!id || id === PLACEHOLDER_ID) return null;
  return id;
}

export function isMockMode(): boolean {
  return resolveResourceIdFromEnv() === null;
}
```

```typescript
// lib/external-api/client.ts
import { google } from "googleapis";

let client: ReturnType<typeof google.sheets> | null = null;

export function getSheetsClient() {
  if (client) return client;

  const keyJson = process.env["SERVICE_ACCOUNT_KEY"];
  if (!keyJson) throw new Error("SERVICE_ACCOUNT_KEY is not set");

  let credentials: Record<string, unknown>;
  try {
    credentials = JSON.parse(keyJson) as Record<string, unknown>;
  } catch {
    throw new Error("SERVICE_ACCOUNT_KEY is invalid JSON. Set one-line JSON string.");
  }

  const auth = new google.auth.GoogleAuth({
    credentials,
    scopes: ["https://www.googleapis.com/auth/spreadsheets"],
  });

  client = google.sheets({ version: "v4", auth });
  return client;
}
```

**ポイント**:
- `process.env["KEY"]` ブラケット記法 → Next.jsの静的最適化/インライン化を回避し、ランタイムで確実に読み取る
- サービスアカウントJSONキーは1行のJSON文字列として環境変数に格納
- クライアントをシングルトン化（モジュールスコープ変数）してコネクション再利用
- プレースホルダー値チェックで未設定状態を明確に判定
- env未設定時は `null` を返し、呼び出し側でモックフォールバック
