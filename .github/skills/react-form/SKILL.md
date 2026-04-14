---
name: react-form
description: >
  React 19 のフォーム機能（<form> action・useActionState・useFormStatus・useOptimistic）の
  正しい使い方・パターン・アンチパターンを、公式ドキュメント（ja.react.dev）に基づいて解説するスキル。
  クライアントサイドのフォーム実装に使用する。RSC / サーバ関数はスコープ外。
sources:
  - https://ja.react.dev/reference/react-dom/components/form
  - https://ja.react.dev/reference/react-dom/hooks/useFormStatus
  - https://ja.react.dev/reference/react/useActionState
react_version: "19.x"
scope: "クライアントフォームのみ（サーバ関数・RSC はスコープ外）"
---

# React 19 フォーム — 完全ガイド（公式ドキュメントベース）

## 0. React 19 のフォームで何が変わったか

React 19 では `<form>` の `action` prop に**関数を直接渡せる**ようになり、
`onSubmit` + `e.preventDefault()` + `useState` という定型コードを書かずに済む場面が増えた。

| 従来（React 18 以前） | React 19 以降 |
|----------------------|--------------|
| `onSubmit` で `e.preventDefault()` | `action={fn}` に関数を渡すだけ |
| `useState` で各フィールド管理 | `FormData` API でまとめて取得 |
| 送信中状態を自前の `useState` で管理 | `useFormStatus` の `pending` を使う |
| アクション結果を `useState` で管理 | `useActionState` でアクションと state を一元管理 |
| 送信後のリセットを手動実装 | 非制御フィールドは送信成功後に**自動リセット** |

---

## 1. API 早見表

| API | 所属 | 役割 |
|-----|------|------|
| `<form action={fn}>` | `react-dom` | フォーム送信を関数にルーティング |
| `useActionState(fn, initialState)` | `react` | アクションの結果 state・pending・アクション関数を返す |
| `useFormStatus()` | `react-dom` | 親 `<form>` の送信中状態（pending・data・method・action）を子から読む |
| `useOptimistic(state, updateFn)` | `react` | 送信完了前にUIを先行更新する楽観的更新 |

---

## 2. `<form action={fn}>` — 基本

### 最小構成

```tsx
export default function Search() {
  function search(formData: FormData) {
    const query = formData.get('query') as string;
    console.log('検索:', query);
  }

  return (
    <form action={search}>
      <input name="query" />
      <button type="submit">Search</button>
    </form>
  );
}
```

**ポイント：**
- `action` に渡す関数は `FormData` を第1引数として受け取る
- 関数は同期・非同期どちらでもよい（`async` 可）
- `action` に関数を渡した場合、HTTP メソッドは `method` の値に関わらず常に `POST`
- アクションが**成功した後**、非制御（`value` を渡していない）フィールドは**自動リセット**される

### FormData から値を取得する

```tsx
async function handleSubmit(formData: FormData) {
  const name     = formData.get('name') as string;
  const email    = formData.get('email') as string;
  const tags     = formData.getAll('tag') as string[]; // 複数値
  const file     = formData.get('avatar') as File;

  // バリデーション・送信処理...
}
```

### ボタン単位で action を上書きする

`<button>` や `<input type="submit">` の `formAction` prop で、
フォームレベルの `action` を上書きできる。

```tsx
function OrderForm() {
  async function saveDraft(formData: FormData) { /* ... */ }
  async function submitOrder(formData: FormData) { /* ... */ }

  return (
    <form action={submitOrder}>
      <input name="item" />
      {/* このボタンだけ別のアクションを使う */}
      <button type="submit" formAction={saveDraft}>下書き保存</button>
      <button type="submit">注文確定</button>
    </form>
  );
}
```

---

## 3. `useActionState` — アクション結果と pending を一元管理

### シグネチャ

```tsx
const [state, formAction, isPending] = useActionState(fn, initialState);
```

| 返り値 | 型 | 説明 |
|-------|-----|------|
| `state` | `S` | アクションが返した最新値。初回は `initialState` |
| `formAction` | `function` | `<form action>` や `<button formAction>` に渡すアクション |
| `isPending` | `boolean` | アクション実行中かどうか |

### アクション関数のシグネチャ

```tsx
// useActionState でラップするアクションは
// 第1引数に「前回 state（または initialState）」が追加される
async function myAction(previousState: State, formData: FormData): Promise<State> {
  // ...
  return nextState;
}
```

> **注意：** `useActionState` でラップした後に `formData` は **第2引数**になる。
> 直接 `<form action>` に渡す場合（ラップなし）は `formData` が第1引数なのと異なる。

### パターン A：バリデーションエラーの表示

```tsx
import { useActionState } from 'react';

type FormState = {
  errors: Record<string, string>;
  success: boolean;
} | null;

async function registerAction(
  prevState: FormState,
  formData: FormData
): Promise<FormState> {
  const email = formData.get('email') as string;
  const password = formData.get('password') as string;

  // クライアントサイドバリデーション
  const errors: Record<string, string> = {};
  if (!email.includes('@')) errors.email = '有効なメールアドレスを入力してください';
  if (password.length < 8)  errors.password = 'パスワードは8文字以上にしてください';
  if (Object.keys(errors).length > 0) return { errors, success: false };

  // API 送信
  const res = await fetch('/api/register', {
    method: 'POST',
    body: JSON.stringify({ email, password }),
    headers: { 'Content-Type': 'application/json' },
  });

  if (!res.ok) {
    const { message } = await res.json();
    return { errors: { form: message }, success: false };
  }

  return { errors: {}, success: true };
}

export function RegisterForm() {
  const [state, formAction, isPending] = useActionState(registerAction, null);

  if (state?.success) {
    return <p>登録が完了しました！</p>;
  }

  return (
    <form action={formAction}>
      <div>
        <input name="email" type="email" placeholder="メールアドレス" />
        {state?.errors.email && <p style={{ color: 'red' }}>{state.errors.email}</p>}
      </div>
      <div>
        <input name="password" type="password" placeholder="パスワード" />
        {state?.errors.password && <p style={{ color: 'red' }}>{state.errors.password}</p>}
      </div>
      {state?.errors.form && <p style={{ color: 'red' }}>{state.errors.form}</p>}
      <button type="submit" disabled={isPending}>
        {isPending ? '登録中...' : '登録'}
      </button>
    </form>
  );
}
```

### パターン B：複数ボタン（送信タイプの分岐）

`formData.get()` で送信元ボタンを識別できる。

```tsx
async function cartAction(prevState: string | null, formData: FormData) {
  const intent = formData.get('intent') as string;
  const itemId = formData.get('itemId') as string;

  if (intent === 'add')    return await addToCart(itemId);
  if (intent === 'remove') return await removeFromCart(itemId);
  return prevState;
}

function CartItem({ itemId }: { itemId: string }) {
  const [message, formAction] = useActionState(cartAction, null);

  return (
    <form action={formAction}>
      <input type="hidden" name="itemId" value={itemId} />
      <button type="submit" name="intent" value="add">カートに追加</button>
      <button type="submit" name="intent" value="remove">削除</button>
      {message && <p>{message}</p>}
    </form>
  );
}
```

### useActionState を使わずに action だけ使うケース

state の返却が不要なシンプルな処理（ナビゲーション・ログ送信など）では
`useActionState` を使わず `action={fn}` だけで十分。

```tsx
function SearchForm() {
  function search(formData: FormData) {
    const q = formData.get('q') as string;
    window.location.href = `/search?q=${encodeURIComponent(q)}`;
  }
  return (
    <form action={search}>
      <input name="q" />
      <button type="submit">検索</button>
    </form>
  );
}
```

---

## 4. `useFormStatus` — 子コンポーネントから親フォームの状態を読む

### シグネチャ

```tsx
const { pending, data, method, action } = useFormStatus();
```

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `pending` | `boolean` | 親 `<form>` が送信中なら `true` |
| `data` | `FormData \| null` | 送信中のフォームデータ（送信中でなければ `null`） |
| `method` | `'get' \| 'post'` | 親フォームの HTTP メソッド |
| `action` | `function \| null` | 親フォームの `action` に渡された関数（URL の場合は `null`） |

### ✅ 正しい使い方：`<form>` の**子コンポーネント**内で呼ぶ

```tsx
// ✅ 専用の子コンポーネントに切り出す
function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <button type="submit" disabled={pending}>
      {pending ? '送信中...' : '送信'}
    </button>
  );
}

function MyForm() {
  return (
    <form action={handleSubmit}>
      <input name="name" />
      <SubmitButton />  {/* ← form の子コンポーネント内で useFormStatus を使う */}
    </form>
  );
}
```

### ❌ よくある間違い：`<form>` と同じコンポーネントで呼ぶ

```tsx
// ❌ pending は常に false — 自分がレンダーする <form> は追跡しない
function MyForm() {
  const { pending } = useFormStatus(); // 動かない！

  return (
    <form action={handleSubmit}>
      <button disabled={pending}>送信</button>
    </form>
  );
}
```

`useFormStatus` は**親の** `<form>` の状態だけを追跡する。
同一コンポーネントや子コンポーネントでレンダーされた `<form>` は対象外。

### 送信中のデータを表示する

```tsx
function SubmitStatus() {
  const { pending, data } = useFormStatus();

  if (!pending || !data) return null;

  const username = data.get('username') as string;
  return <p>「{username}」を登録中...</p>;
}
```

### useFormStatus と useActionState の使い分け

| ニーズ | 使うもの |
|--------|---------|
| ボタンや入力を `pending` 中に無効化したい | `useFormStatus` （子コンポーネントに切り出す） |
| アクションが返した値（エラー・成功メッセージ）を表示したい | `useActionState` |
| pending を **フォームと同じコンポーネント**で取得したい | `useActionState` の `isPending` |

---

## 5. `useOptimistic` — 楽観的更新

サーバの応答を待たずに UI を先行更新し、完了後に確定する。

### シグネチャ

```tsx
const [optimisticState, addOptimistic] = useOptimistic(state, updateFn);
```

### 実装例：メッセージ送信

```tsx
import { useOptimistic, useState, useRef } from 'react';

type Message = { text: string; sending?: boolean };

function MessageThread({
  messages,
  sendMessage,
}: {
  messages: Message[];
  sendMessage: (formData: FormData) => Promise<void>;
}) {
  const formRef = useRef<HTMLFormElement>(null);

  const [optimisticMessages, addOptimisticMessage] = useOptimistic(
    messages,
    // updateFn: 楽観的な state をどう作るか
    (currentMessages, newText: string) => [
      ...currentMessages,
      { text: newText, sending: true },
    ]
  );

  async function formAction(formData: FormData) {
    const text = formData.get('message') as string;
    // 即座に UI に反映（sending: true 付き）
    addOptimisticMessage(text);
    // フォームをリセット
    formRef.current?.reset();
    // 実際の送信（完了後に sending フラグが消える）
    await sendMessage(formData);
  }

  return (
    <>
      {optimisticMessages.map((msg, i) => (
        <div key={i}>
          {msg.text}
          {msg.sending && <small> (送信中...)</small>}
        </div>
      ))}
      <form action={formAction} ref={formRef}>
        <input type="text" name="message" placeholder="メッセージ" />
        <button type="submit">送信</button>
      </form>
    </>
  );
}
```

**仕組み：**
1. `addOptimisticMessage(text)` を呼ぶと `sending: true` のメッセージが即座に表示される
2. バックグラウンドで `sendMessage` が実行される
3. 完了後、`messages` state が更新されて `useOptimistic` の楽観的レイヤーが消える

---

## 6. エラーハンドリング

### ErrorBoundary でアクションのエラーを捕捉する

アクション関数が例外をスローした場合は `ErrorBoundary` で捕捉する。

```tsx
import { ErrorBoundary } from 'react-error-boundary';

function SearchForm() {
  async function search(formData: FormData) {
    const result = await fetchSearch(formData.get('q') as string);
    if (!result.ok) throw new Error('検索に失敗しました');
  }

  return (
    <ErrorBoundary fallback={<p>エラーが発生しました</p>}>
      <form action={search}>
        <input name="q" />
        <button type="submit">検索</button>
      </form>
    </ErrorBoundary>
  );
}
```

### useActionState でエラーを state として扱う（推奨）

例外をスローせず、エラー情報を state として返す方がコントロールしやすい。

```tsx
type State = { error: string | null; data: unknown };

async function action(prev: State, formData: FormData): Promise<State> {
  try {
    const data = await fetchSomething(formData);
    return { error: null, data };
  } catch (e) {
    // スローせず state として返す
    return { error: (e as Error).message, data: null };
  }
}

function MyForm() {
  const [state, formAction] = useActionState(action, { error: null, data: null });
  return (
    <form action={formAction}>
      {state.error && <p style={{ color: 'red' }}>{state.error}</p>}
      {/* フィールド */}
    </form>
  );
}
```

---

## 7. 制御フォームとの使い分け

React 19 の `action` ベースのフォームは**非制御フィールド**（`FormData` で値を取る）が基本。
リアルタイムバリデーション・フィールド間の連動など、細かい制御が必要な場合は
`useState` による制御フォームを使う。

| 要件 | 推奨アプローチ |
|------|--------------|
| シンプルな送信・バリデーションエラー表示 | `<form action>` + `useActionState` |
| 送信中状態の表示（ボタン無効化など） | `useFormStatus` （子コンポーネント） |
| 楽観的 UI 更新 | `useOptimistic` |
| 入力のたびにリアルタイムバリデーション | `useState` + `onChange` の制御フォーム |
| フィールド間の値連動（条件付き表示など） | `useState` + `onChange` の制御フォーム |
| 複雑なフォーム（100 フィールド超・ウィザードなど） | React Hook Form / Zod などのライブラリ |

---

## 8. よくある実装パターン集

### シンプルな問い合わせフォーム

```tsx
import { useActionState } from 'react';

type ContactState = { success: boolean; error: string | null } | null;

async function contactAction(prev: ContactState, formData: FormData): Promise<ContactState> {
  const name    = formData.get('name') as string;
  const message = formData.get('message') as string;

  if (!name || !message) return { success: false, error: '全ての項目を入力してください' };

  await fetch('/api/contact', {
    method: 'POST',
    body: JSON.stringify({ name, message }),
    headers: { 'Content-Type': 'application/json' },
  });

  return { success: true, error: null };
}

export function ContactForm() {
  const [state, formAction, isPending] = useActionState(contactAction, null);

  if (state?.success) return <p>お問い合わせを受け付けました。</p>;

  return (
    <form action={formAction}>
      {state?.error && <p style={{ color: 'red' }}>{state.error}</p>}
      <input name="name" placeholder="お名前" required />
      <textarea name="message" placeholder="お問い合わせ内容" required />
      <button type="submit" disabled={isPending}>
        {isPending ? '送信中...' : '送信'}
      </button>
    </form>
  );
}
```

### 再利用可能な SubmitButton コンポーネント

```tsx
import { useFormStatus } from 'react-dom';

interface SubmitButtonProps {
  label?: string;
  pendingLabel?: string;
  className?: string;
}

export function SubmitButton({
  label = '送信',
  pendingLabel = '送信中...',
  className,
}: SubmitButtonProps) {
  const { pending } = useFormStatus();
  return (
    <button type="submit" disabled={pending} className={className}>
      {pending ? pendingLabel : label}
    </button>
  );
}

// 使い方
function AnyForm() {
  return (
    <form action={someAction}>
      <input name="value" />
      <SubmitButton label="保存" pendingLabel="保存中..." />
    </form>
  );
}
```

### フォームリセット（送信成功後に手動リセットが必要な場合）

非制御フィールドは送信成功後に自動リセットされるが、
制御フィールドや特殊なケースでは `useRef` でリセットする。

```tsx
function FormWithReset() {
  const formRef = useRef<HTMLFormElement>(null);

  async function handleAction(formData: FormData) {
    await submitData(formData);
    // 手動リセットが必要な場合
    formRef.current?.reset();
  }

  return (
    <form action={handleAction} ref={formRef}>
      <input name="comment" />
      <button type="submit">投稿</button>
    </form>
  );
}
```

---

## 9. アンチパターン

### ❌ `onSubmit` + `e.preventDefault()` を React 19 でも使い続ける

```tsx
// ❌ React 19 では不要なボイラープレート
function OldForm() {
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setLoading(true);
    const formData = new FormData(e.currentTarget);
    await submitData(formData);
    setLoading(false);
  }

  return (
    <form onSubmit={handleSubmit}>
      <input name="value" />
      <button disabled={loading}>送信</button>
    </form>
  );
}

// ✅ React 19 スタイル
function NewForm() {
  const [state, formAction, isPending] = useActionState(submitAction, null);

  return (
    <form action={formAction}>
      <input name="value" />
      <button disabled={isPending}>送信</button>
    </form>
  );
}
```

### ❌ `useFormStatus` をフォームと同じコンポーネントで使う

```tsx
// ❌ pending は常に false
function BadForm() {
  const { pending } = useFormStatus(); // 機能しない
  return <form action={action}><button disabled={pending}>送信</button></form>;
}

// ✅ 子コンポーネントに分離する
function GoodForm() {
  return <form action={action}><SubmitButton /></form>;
}
function SubmitButton() {
  const { pending } = useFormStatus(); // ✅ 親 <form> の状態を追跡
  return <button disabled={pending}>送信</button>;
}
```

### ❌ useActionState のアクション引数を間違える

```tsx
// ❌ useActionState でラップしているのに formData を第1引数で受け取っている
async function wrongAction(formData: FormData) { // 実際は prevState が第1引数
  const value = formData.get('value'); // undefined になる
}

// ✅ 第1引数は前回 state、第2引数が formData
async function correctAction(prevState: State, formData: FormData) {
  const value = formData.get('value'); // ✅ 正しく取得できる
}
```

---

## 10. 判断フローチャート

```
フォームを実装したい
        ↓
リアルタイムバリデーション・フィールド間連動が必要？
  YES → useState + onChange の制御フォーム
         （複雑なら React Hook Form / Zod も検討）
  NO  ↓
<form action={fn}> をベースに実装
        ↓
アクションの結果（エラー・成功メッセージ）を表示したい？
  YES → useActionState(fn, initialState) でラップ
         → state にエラー/成功情報を返す
  NO  ↓
送信中状態（ボタン無効化など）を表示したい？
  YES → SubmitButton を子コンポーネントに切り出して useFormStatus を使う
  または → useActionState の isPending を使う
  NO  ↓
送信前に UI を楽観的更新したい？
  YES → useOptimistic を使う
  NO  ↓
シンプルな <form action={fn}> だけで完結
        ↓
アクションが例外をスローする可能性がある？
  YES → ErrorBoundary でラップ
       または useActionState でエラーを state として返す（推奨）
```
