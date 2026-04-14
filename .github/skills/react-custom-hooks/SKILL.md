---
name: react-custom-hooks
description: >
  React カスタムフックの設計・命名・切り出しタイミング・アンチパターン・イベントハンドラの受け渡しを、
  公式ドキュメント（ja.react.dev）に基づいて解説するスキル。
  ロジックの重複を発見したとき・エフェクトの抽出を検討するときに使用する。
sources:
  - https://ja.react.dev/learn/reusing-logic-with-custom-hooks
react_version: "19.x"
---

# React カスタムフック — 完全ガイド（公式ドキュメントベース）

## 0. カスタムフックとは何か

カスタムフックとは、**`use` で始まる名前を持ち、内部で他のフックを呼び出す関数**のこと。
コンポーネントは「何を表示するか」に集中でき、「どうやって実現するか」の詳細はフックに隠蔽される。

> **カスタムフックは state 自体ではなく、state を扱うロジックを共有する。**

同じカスタムフックを複数の場所で呼び出しても、それぞれが**完全に独立した state とエフェクト**を持つ。
コンポーネント間で state 自体を共有したいなら、[state のリフトアップ](https://ja.react.dev/learn/sharing-state-between-components)を使う。

---

## 1. 命名規則

### 絶対に守るルール

```
use + 大文字で始まる名前
```

```tsx
// ✅ カスタムフック
function useOnlineStatus() { ... }
function useFormInput(initialValue) { ... }
function useChatRoom(options) { ... }
function useData(url) { ... }

// ❌ フックではない通常の関数（usePrefix 不要）
function getSorted(items) { ... }   // フックを呼ばないなら use は付けない
function getColor(theme) { ... }    // 同上
```

**判断基準：内部で 1 つ以上のフックを呼ぶ → `use` を付ける。フックを呼ばない → `use` を付けない。**

リンタ（`eslint-plugin-react-hooks`）がこの規約を強制する。
`use` なし関数の中でフックを呼ぶとリントエラーになる。

### 良い名前の特徴

コードをあまり書かない人でも「何をするか・何を受け取るか・何を返すか」が推測できること。

```tsx
// ✅ 具体的・高レベル
useData(url)
useFormInput(initialValue)
useOnlineStatus()
useWindowSize()
useIntersectionObserver(ref, options)
useMediaQuery(query)
useSocket(url)
useChatRoom({ roomId, serverUrl })

// ❌ ライフサイクル名をそのまま使った抽象的すぎるもの（後述）
useMount(fn)
useEffectOnce(fn)
useUpdateEffect(fn)
```

---

## 2. 基本的な切り出しパターン

### パターン A：複数コンポーネントで重複するロジック

同じ `useState` + `useEffect` の組み合わせが複数コンポーネントに現れたら抽出のサイン。

**切り出し前（重複あり）：**

```tsx
// StatusBar.tsx
function StatusBar() {
  const [isOnline, setIsOnline] = useState(true);
  useEffect(() => {
    function handleOnline()  { setIsOnline(true); }
    function handleOffline() { setIsOnline(false); }
    window.addEventListener('online',  handleOnline);
    window.addEventListener('offline', handleOffline);
    return () => {
      window.removeEventListener('online',  handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, []);
  return <h1>{isOnline ? '✅ Online' : '❌ Disconnected'}</h1>;
}

// SaveButton.tsx — 全く同じ state + Effect が重複
function SaveButton() {
  const [isOnline, setIsOnline] = useState(true);
  useEffect(() => { /* 同じコード */ }, []);
  return <button disabled={!isOnline}>{isOnline ? 'Save' : 'Reconnecting...'}</button>;
}
```

**切り出し後：**

```tsx
// hooks/useOnlineStatus.ts
import { useState, useEffect } from 'react';

export function useOnlineStatus(): boolean {
  const [isOnline, setIsOnline] = useState(true);

  useEffect(() => {
    function handleOnline()  { setIsOnline(true); }
    function handleOffline() { setIsOnline(false); }
    window.addEventListener('online',  handleOnline);
    window.addEventListener('offline', handleOffline);
    return () => {
      window.removeEventListener('online',  handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, []);

  return isOnline;
}

// 各コンポーネントは「何をしたいか」だけを記述
function StatusBar() {
  const isOnline = useOnlineStatus(); // ← 実装の詳細を知らなくてよい
  return <h1>{isOnline ? '✅ Online' : '❌ Disconnected'}</h1>;
}

function SaveButton() {
  const isOnline = useOnlineStatus();
  return <button disabled={!isOnline}>{isOnline ? 'Save' : 'Reconnecting...'}</button>;
}
```

---

### パターン B：1コンポーネント内の類似した繰り返し

同じフォームフィールドのロジックが複数回登場する場合。

```tsx
// hooks/useFormInput.ts
import { useState } from 'react';

export function useFormInput(initialValue: string) {
  const [value, setValue] = useState(initialValue);

  return {
    value,
    onChange: (e: React.ChangeEvent<HTMLInputElement>) => setValue(e.target.value),
  };
}

// 呼び出し側 — useFormInput を2回呼ぶと独立した state が2つ生まれる
function Form() {
  const firstNameProps = useFormInput('Mary');
  const lastNameProps  = useFormInput('Poppins');

  return (
    <>
      <input {...firstNameProps} />  {/* value と onChange が展開される */}
      <input {...lastNameProps}  />
    </>
  );
}
```

**重要：** `useFormInput` を2回呼んでも state は**別々**。共有されない。

---

### パターン C：エフェクトを伴うデータ取得

複数の独立したデータ取得エフェクトが並ぶ場合は共通部分を抽出する。

**切り出し前：**

```tsx
function ShippingForm({ country }) {
  const [cities, setCities] = useState(null);
  useEffect(() => {
    let ignore = false;
    fetch(`/api/cities?country=${country}`)
      .then(r => r.json())
      .then(json => { if (!ignore) setCities(json); });
    return () => { ignore = true; };
  }, [country]);

  const [city, setCity] = useState(null);
  const [areas, setAreas] = useState(null);
  useEffect(() => {
    if (!city) return;
    let ignore = false;
    fetch(`/api/areas?city=${city}`)
      .then(r => r.json())
      .then(json => { if (!ignore) setAreas(json); });
    return () => { ignore = true; };
  }, [city]);
  // ...
}
```

**切り出し後：**

```tsx
// hooks/useData.ts
function useData<T>(url: string | null): T | null {
  const [data, setData] = useState<T | null>(null);

  useEffect(() => {
    if (!url) return;
    let ignore = false;
    fetch(url)
      .then(r => r.json())
      .then((json: T) => { if (!ignore) setData(json); });
    return () => { ignore = true; };
  }, [url]);

  return data;
}

// 呼び出し側 — データフローが明示的になる
function ShippingForm({ country }) {
  const cities = useData<City[]>(`/api/cities?country=${country}`);
  const [city, setCity] = useState<string | null>(null);
  const areas  = useData<Area[]>(city ? `/api/areas?city=${city}` : null);
  // ...
}
```

---

## 3. フック間でリアクティブな値を渡す

カスタムフックはコンポーネントと一緒に再レンダーされる。
そのため、引数として渡したリアクティブな値（props・state）が変わると、フック内部のエフェクトも適切に再実行される。

```tsx
// hooks/useChatRoom.ts
import { useEffect } from 'react';

interface Options {
  serverUrl: string;
  roomId: string;
}

export function useChatRoom({ serverUrl, roomId }: Options) {
  useEffect(() => {
    const connection = createConnection({ serverUrl, roomId });
    connection.connect();
    return () => connection.disconnect();
  }, [serverUrl, roomId]); // リアクティブな値は依存配列に列挙
}

// 呼び出し側
function ChatRoom({ roomId }) {
  const [serverUrl, setServerUrl] = useState('https://localhost:1234');

  // serverUrl や roomId が変わると useChatRoom 内のエフェクトが再同期される
  useChatRoom({ serverUrl, roomId });
  // ...
}
```

**フックのチェーン：** ある useState の出力を別のカスタムフックの入力として渡せる。
これにより、音声・映像エフェクトのチェーンのように、段階的なデータフローが構築できる。

---

## 4. イベントハンドラをカスタムフックに渡す

コールバックを props として受け取り、エフェクト内で使いたい場合、
そのまま依存配列に入れると再レンダーのたびに再接続が起きる。
**`useEffectEvent` でラップして依存配列から除外する。**

```tsx
// ❌ 問題：onReceiveMessage が依存配列にあると毎レンダーで再接続
export function useChatRoom({ serverUrl, roomId, onReceiveMessage }) {
  useEffect(() => {
    const connection = createConnection({ serverUrl, roomId });
    connection.on('message', onReceiveMessage);
    connection.connect();
    return () => connection.disconnect();
  }, [serverUrl, roomId, onReceiveMessage]); // 毎レンダーで新しい関数参照 → 再接続
}

// ✅ 解決：useEffectEvent でラップして最新値を参照しつつ依存から外す
import { useEffect, useEffectEvent } from 'react';

export function useChatRoom({ serverUrl, roomId, onReceiveMessage }) {
  const onMessage = useEffectEvent(onReceiveMessage); // 常に最新のコールバックを参照

  useEffect(() => {
    const connection = createConnection({ serverUrl, roomId });
    connection.on('message', (msg) => onMessage(msg));
    connection.connect();
    return () => connection.disconnect();
  }, [serverUrl, roomId]); // onMessage は不要
}

// 呼び出し側 — ロジックをコンポーネント側に残せる
function ChatRoom({ roomId }) {
  const [serverUrl, setServerUrl] = useState('https://localhost:1234');

  useChatRoom({
    serverUrl,
    roomId,
    onReceiveMessage(msg) {
      showNotification('New message: ' + msg);
    },
  });
  // ...
}
```

---

## 5. 切り出すタイミング・切り出さないタイミング

### ✅ 切り出すべきとき

| シグナル | 例 |
|---------|---|
| 同じ state + Effect の組み合わせが複数コンポーネントに登場する | `useOnlineStatus`、`useWindowSize` |
| エフェクトがあり、意図を一言で説明できる名前をつけられる | `useData(url)`、`useChatRoom(options)` |
| 外部システム・ブラウザ API との同期を隠蔽したい | `useIntersectionObserver`、`useMediaQuery` |
| コンポーネントから「どのように」の詳細を隠し「何をしたいか」だけを残したい | `useFormInput`、`useAuth` |

### ❌ 切り出さなくていいとき

- 単純な `useState` を 1 つラップするだけで意図が明確でない
- ロジックが特定のコンポーネントに密接に結びついており、汎用化の見込みがない
- コードの重複が 1〜2 箇所しかなく、まだパターンが見えていない

---

## 6. 絶対に避けるべきアンチパターン

### ライフサイクルフック（`useMount` など）

```tsx
// ❌ 絶対に避ける — React のパラダイムと相容れない
function useMount(fn: () => void) {
  useEffect(() => {
    fn();
  }, []); // 🔴 fn が依存配列にない → リントエラー & バグの温床
}

function ChatRoom({ roomId, serverUrl }) {
  useMount(() => {
    const connection = createConnection({ roomId, serverUrl });
    connection.connect(); // roomId / serverUrl の変化に反応しない！
  });
}
```

**問題点：**
- リンタは `useEffect` の直接呼び出しだけをチェックする。カスタムフックの中身は検証しない。
- 依存配列の警告が出ないため、`roomId` が変わっても再接続されないバグが潜伏する。
- 「マウント時だけ実行」という発想自体が React のリアクティブモデルと相性が悪い。

```tsx
// ✅ 正しいアプローチ — useEffect を直接使い、依存配列を正直に書く
function ChatRoom({ roomId, serverUrl }) {
  useEffect(() => {
    const connection = createConnection({ serverUrl, roomId });
    connection.connect();
    return () => connection.disconnect();
  }, [serverUrl, roomId]); // 変化に正しく反応する
}

// 抽出するなら高レベルな意図を名前に込める
function useChatRoom({ serverUrl, roomId }: Options) {
  useEffect(() => {
    const connection = createConnection({ serverUrl, roomId });
    connection.connect();
    return () => connection.disconnect();
  }, [serverUrl, roomId]);
}
```

---

## 7. カスタムフックの構造テンプレート

### 基本形：値を返すフック

```tsx
// hooks/useXxx.ts
import { useState, useEffect } from 'react';

interface UseXxxOptions {
  /* 引数の型 */
}

interface UseXxxReturn {
  /* 返り値の型 */
}

export function useXxx(options: UseXxxOptions): UseXxxReturn {
  const [value, setValue] = useState(/* 初期値 */);

  useEffect(() => {
    // 外部システムとの同期ロジック
    return () => {
      // クリーンアップ
    };
  }, [/* リアクティブな依存値 */]);

  return { value /* , その他 */ };
}
```

### イベントハンドラを受け取るフック

```tsx
import { useEffect, useEffectEvent } from 'react';

interface UseXxxOptions {
  param: string;
  onEvent: (data: unknown) => void; // コールバック
}

export function useXxx({ param, onEvent }: UseXxxOptions) {
  // コールバックは useEffectEvent でラップして依存配列から除外
  const handleEvent = useEffectEvent(onEvent);

  useEffect(() => {
    const subscription = subscribe(param, (data) => handleEvent(data));
    return () => subscription.unsubscribe();
  }, [param]); // onEvent は依存配列不要
}
```

### 複数の値・関数を返すフック

```tsx
export function useCounter(initial = 0) {
  const [count, setCount] = useState(initial);

  const increment = useCallback(() => setCount(c => c + 1), []);
  const decrement = useCallback(() => setCount(c => c - 1), []);
  const reset     = useCallback(() => setCount(initial),    [initial]);

  return { count, increment, decrement, reset };
}
```

---

## 8. TypeScript での型付けパターン

```tsx
// ① ジェネリクスで汎用化
function useLocalStorage<T>(key: string, initialValue: T): [T, (value: T) => void] {
  const [stored, setStored] = useState<T>(() => {
    try {
      const item = window.localStorage.getItem(key);
      return item ? JSON.parse(item) : initialValue;
    } catch {
      return initialValue;
    }
  });

  const setValue = (value: T) => {
    setStored(value);
    window.localStorage.setItem(key, JSON.stringify(value));
  };

  return [stored, setValue];
}

// ② オプション型をインターフェースに切り出す（引数が増えても破壊的変更なし）
interface UseFetchOptions<T> {
  url: string | null;
  transform?: (raw: unknown) => T;
}

function useFetch<T>({ url, transform }: UseFetchOptions<T>) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<Error | null>(null);
  const [loading, setLoading] = useState(false);
  // ...
  return { data, error, loading };
}

// ③ 返り値をタプルにするか オブジェクトにするか
// タプル → 呼び出し側でリネームしやすい（useState スタイル）
function useToggle(initial = false): [boolean, () => void] { ... }
const [isOpen, toggleOpen] = useToggle();

// オブジェクト → 返り値が多い場合・名前が重要な場合
function useFormInput(initialValue: string) { ... }
const emailInput = useFormInput('');
const passwordInput = useFormInput('');
```

---

## 9. よくある実装パターン集

### useWindowSize

```tsx
function useWindowSize() {
  const [size, setSize] = useState({
    width: window.innerWidth,
    height: window.innerHeight,
  });

  useEffect(() => {
    function handleResize() {
      setSize({ width: window.innerWidth, height: window.innerHeight });
    }
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, []);

  return size;
}
```

### useDebounce

```tsx
function useDebounce<T>(value: T, delay: number): T {
  const [debounced, setDebounced] = useState(value);

  useEffect(() => {
    const id = setTimeout(() => setDebounced(value), delay);
    return () => clearTimeout(id);
  }, [value, delay]);

  return debounced;
}
```

### usePrevious（前回の値を記憶）

```tsx
function usePrevious<T>(value: T): T | undefined {
  const ref = useRef<T | undefined>(undefined);

  useEffect(() => {
    ref.current = value; // コミット後に更新
  });

  return ref.current; // レンダー中は前回の値
}
```

### useMediaQuery

```tsx
function useMediaQuery(query: string): boolean {
  const [matches, setMatches] = useState(
    () => window.matchMedia(query).matches
  );

  useEffect(() => {
    const mql = window.matchMedia(query);
    const handler = (e: MediaQueryListEvent) => setMatches(e.matches);
    mql.addEventListener('change', handler);
    return () => mql.removeEventListener('change', handler);
  }, [query]);

  return matches;
}
```

---

## 10. 判断フローチャート

```
ロジックを切り出したい・重複がある
        ↓
フックを呼ばない純粋な計算ロジック？
  YES → 通常の関数（use プレフィックス不要）
  NO  ↓
複数のコンポーネント間で使い回したいか？
または 1コンポーネント内でも意図を名前で表現したいか？
  NO  → そのまま useEffect / useState を直接書く
  YES ↓
「何をするか」を一言で表す名前が思いつくか？
  NO  → まだ抽出しない（パターンが見えていない）
  YES ↓
命名チェック：
  - use + 大文字で始まるか？  ✅
  - ライフサイクル名（useMount 等）になっていないか？  ✅
  - 具体的なユースケース名になっているか？  ✅
        ↓
引数にコールバック（イベントハンドラ）を受け取るか？
  YES → useEffectEvent でラップして依存配列から除外
  NO  ↓
リアクティブな引数（props・state 由来の値）を受け取るか？
  YES → 依存配列に漏れなく列挙する（リンタに従う）
        ↓
完成：フックをエクスポートしてコンポーネントに適用
```

---

## 11. ベストプラクティス まとめ

- **`use` + 大文字で始める命名規則**は必ず守る。フックを呼ばない関数には `use` を付けない
- **ライフサイクルフック（`useMount` 等）は作らない**。React のリアクティブモデルと相容れない
- **カスタムフックは state 自体でなくロジックを共有する**。同一フックの複数呼び出しは独立した state を持つ
- **イベントハンドラを受け取るフックは `useEffectEvent` でラップ**して依存配列から除外する
- **エフェクトを書いたら常に抽出を検討する**。エフェクトはそれ自体が「外部システムとの同期」であり、名前をつけられる意図を持つはず
- **名前が思いつかなければまだ抽出しない**。意図が明確になってから切り出す
- **`useData(url)` のような汎用フックより `useChatRoom(options)` のような具体的フックを優先**。意図が伝わる粒度に設計する
- **カスタムフックのコードはコンポーネント本体の一部と同じ**。コンポーネントの再レンダーごとに実行され、常に最新の props・state を受け取る
