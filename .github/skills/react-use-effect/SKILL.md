---
name: react-use-effect
description: >
  React の useEffect フックに関する正しい使い方・アンチパターン・依存配列の扱い・クリーンアップ・useEffectEvent の活用などを、公式ドキュメント（ja.react.dev）に基づいて解説するスキル。
  エフェクトを書く前・書いた後の判断に必ず使用すること。
sources:
  - https://ja.react.dev/learn/you-might-not-need-an-effect
  - https://ja.react.dev/learn/synchronizing-with-effects
  - https://ja.react.dev/learn/lifecycle-of-reactive-effects
  - https://ja.react.dev/learn/separating-events-from-effects
  - https://ja.react.dev/learn/removing-effect-dependencies
react_version: "19.x"
---

# React useEffect — 完全ガイド（公式ドキュメントベース）

## 0. 最初に問うべき質問

エフェクトを書こうとしたら、まず自問する：

> **「外部システムとの同期が本当に必要か？」**

エフェクトは「React の外に踏み出す」ための避難ハッチ。ブラウザ DOM API・サードパーティライブラリ・ネットワーク接続など、**React が管理できない外部システムと同期するためだけに使う**。

それ以外の用途では、ほぼ必ずエフェクトは不要。

---

## 1. エフェクトとは何か

### イベントとの違い

| 種類 | トリガ | 例 |
|------|--------|----|
| **イベントハンドラ** | 特定のユーザ操作 | ボタンクリックで POST リクエスト |
| **エフェクト** | レンダー自体 | コンポーネント表示中は常にサーバ接続を維持 |

エフェクトはコミット（DOM 更新）の後、画面が更新されてから実行される。

### 基本構文

```tsx
import { useEffect } from 'react';

function MyComponent() {
  useEffect(() => {
    // 同期開始のロジック
    const connection = createConnection();
    connection.connect();

    // クリーンアップ（同期停止のロジック）
    return () => {
      connection.disconnect();
    };
  }, [dependency]); // 依存配列
}
```

---

## 2. エフェクトが不要なケース（アンチパターン集）

### 2-1. props/state から計算できる値を state に入れている

```tsx
// ❌ 不要なエフェクト
const [fullName, setFullName] = useState('');
useEffect(() => {
  setFullName(firstName + ' ' + lastName);
}, [firstName, lastName]);

// ✅ レンダー中に直接計算
const fullName = firstName + ' ' + lastName;
```

**ルール：既存の props や state から導出できるものは state に入れない。レンダー中に計算する。**

### 2-2. 重たい計算をエフェクト+state で管理している

```tsx
// ❌ 不要なエフェクト
const [visibleTodos, setVisibleTodos] = useState([]);
useEffect(() => {
  setVisibleTodos(getFilteredTodos(todos, filter));
}, [todos, filter]);

// ✅ useMemo でメモ化（React Compiler 使用時は不要なことも多い）
const visibleTodos = useMemo(
  () => getFilteredTodos(todos, filter),
  [todos, filter]
);
```

`useMemo` は初回レンダーを速くするものではなく、**再レンダー時の不要な再計算を防ぐ**もの。1ms 以上かかるような計算にのみ使う。

### 2-3. props 変更時に state をリセットするためにエフェクトを使っている

```tsx
// ❌ 非効率：古い値で一度レンダーされてしまう
useEffect(() => {
  setComment('');
}, [userId]);

// ✅ key を使って React に「別のコンポーネント」と認識させる
function ProfilePage({ userId }) {
  return <Profile userId={userId} key={userId} />;
}
// Profile 内の state は key が変わると自動リセット
```

### 2-4. props 変更時に一部の state だけ調整したい

```tsx
// ❌ エフェクトで調整（子が古い値でレンダーされる）
useEffect(() => {
  setSelection(null);
}, [items]);

// ✅ ベスト：selectedId を保持し、選択アイテムはレンダー中に計算
const [selectedId, setSelectedId] = useState(null);
const selection = items.find(item => item.id === selectedId) ?? null;
```

### 2-5. ユーザイベントの処理をエフェクトに書いている

```tsx
// ❌ バグを生む（ページリロード時にも通知が出る）
useEffect(() => {
  if (product.isInCart) {
    showNotification(`Added ${product.name} to cart!`);
  }
}, [product]);

// ✅ イベントハンドラで処理
function handleBuyClick() {
  addToCart(product);
  showNotification(`Added ${product.name} to cart!`);
}
```

**判断基準：「コンポーネントがユーザに表示されたために実行すべきコード」にのみエフェクトを使う。**

### 2-6. データ取得をエフェクトで行うとき（フレームワーク使用時は不要かも）

フレームワーク（Next.js・Remix など）を使っている場合は組み込みのデータ取得機構を使う。素の React の場合のみエフェクトでデータ取得を行い、その際は必ずクリーンアップでキャンセル処理を実装する。

```tsx
useEffect(() => {
  let cancelled = false;
  fetchData(id).then(data => {
    if (!cancelled) setData(data);
  });
  return () => { cancelled = true; };
}, [id]);
```

---

## 3. エフェクトの書き方（3ステップ）

### ステップ1：エフェクトを宣言する

```tsx
useEffect(() => {
  // レンダー後に毎回実行される
});
```

### ステップ2：依存配列を指定する

```tsx
useEffect(() => {
  // isPlaying が変わったときだけ再実行
  if (isPlaying) {
    ref.current.play();
  } else {
    ref.current.pause();
  }
}, [isPlaying]); // ← 依存配列
```

- `[]`（空配列）：マウント時のみ実行
- `[a, b]`：a または b が変わったときに実行
- 依存配列なし：すべてのレンダー後に実行（無限ループに注意）

**依存配列は「選ぶ」ものではなく、コードが読んでいるリアクティブな値を正直に列挙したもの。**

### ステップ3：クリーンアップ関数を返す

```tsx
useEffect(() => {
  const connection = createConnection(serverUrl, roomId);
  connection.connect();

  return () => {
    connection.disconnect(); // 同期停止ロジック
  };
}, [roomId]);
```

クリーンアップは：
- 次のエフェクト実行前
- コンポーネントのアンマウント時

に呼ばれる。

---

## 4. エフェクトのライフサイクル

コンポーネントのライフサイクル（mount/update/unmount）で考えない。エフェクトは：

> **「同期の開始」と「同期の停止」の1サイクル**

だけを考える。

```
roomId = "general"  →  接続開始
roomId = "travel"   →  "general" 切断 → "travel" 接続開始
roomId = "music"    →  "travel" 切断 → "music" 接続開始
アンマウント        →  "music" 切断
```

### 開発環境での2回実行について

React の Strict Mode では開発時にエフェクトが意図的に2回実行される（マウント→クリーンアップ→マウント）。これは「クリーンアップが正しく実装されているか」を確認するための仕様。本番では1回のみ実行される。

---

## 5. リアクティブな値とロジック

コンポーネント本体で宣言された props・state・変数はすべて**リアクティブな値**（再レンダー時に変わりうる）。

```tsx
const serverUrl = 'https://localhost:1234'; // ← リアクティブでない（コンポーネント外）

function ChatRoom({ roomId }) { // ← roomId はリアクティブ
  const [message, setMessage] = useState(''); // ← message はリアクティブ
```

| ロジックの種類 | リアクティブか | 値の変化に反応するか |
|--------------|--------------|-------------------|
| イベントハンドラ内 | ❌ | しない |
| エフェクト内 | ✅ | する（依存配列に必要） |

---

## 6. エフェクトイベント（useEffectEvent）— React 19

**「エフェクトの一部だけをリアクティブにしたくない」**場合に使う。

```tsx
import { useEffect, useEffectEvent } from 'react';

function ChatRoom({ roomId, theme }) {
  // theme の変更でエフェクト全体を再実行したくない
  const onConnected = useEffectEvent(() => {
    showNotification('Connected!', theme); // theme は常に最新値を読む
  });

  useEffect(() => {
    const connection = createConnection(serverUrl, roomId);
    connection.on('connected', () => {
      onConnected(); // theme は依存配列に不要
    });
    connection.connect();
    return () => connection.disconnect();
  }, [roomId]); // theme を依存配列に含めなくてよい
}
```

### useEffectEvent のルール

- エフェクトの**内部からのみ**呼び出す
- 他のコンポーネントやフックに渡さない
- 常に**最新の props/state**を読む（リアクティブでない）

---

## 7. 依存値の削除テクニック

### 7-1. 値がリアクティブである必要がない → コンポーネント外に移動

```tsx
// ❌ コンポーネント内にある → リアクティブ
function ChatRoom() {
  const serverUrl = 'https://localhost:1234'; // 依存配列に必要になる

// ✅ コンポーネント外 → リアクティブでない
const serverUrl = 'https://localhost:1234';
function ChatRoom() {
  // ...
  }, []); // 依存配列が空でよい
```

### 7-2. エフェクト内で state を更新するとき → 更新関数を使う

```tsx
// ❌ count が依存配列に必要になる
useEffect(() => {
  const id = setInterval(() => setCount(count + 1), 1000);
  return () => clearInterval(id);
}, [count]);

// ✅ 更新関数を使えば count は不要
useEffect(() => {
  const id = setInterval(() => setCount(c => c + 1), 1000);
  return () => clearInterval(id);
}, []); // count 不要
```

### 7-3. オブジェクト・関数の依存値 → プリミティブに分解する

オブジェクトや関数はレンダーごとに新しい参照が作られるため、依存配列に入れると毎回再実行される。

```tsx
// ❌ options オブジェクト全体を依存配列に入れると毎レンダー再実行
function ChatRoom({ options }) {
  useEffect(() => {
    const connection = createConnection(options);
    // ...
  }, [options]); // options は毎レンダー新しいオブジェクト

// ✅ 必要なプリミティブ値だけを取り出す
function ChatRoom({ options }) {
  const { roomId, serverUrl } = options;
  useEffect(() => {
    const connection = createConnection({ roomId, serverUrl });
    // ...
  }, [roomId, serverUrl]); // プリミティブなので安定
```

### 7-4. 関数が依存値になる場合 → エフェクト内に移動する

```tsx
// ❌ createOptions がコンポーネント内にあると依存配列に必要
function ChatRoom({ roomId }) {
  function createOptions() {
    return { serverUrl, roomId };
  }
  useEffect(() => {
    const options = createOptions(); // createOptions が依存値に
    // ...
  }, [createOptions]);

// ✅ エフェクト内に移動
function ChatRoom({ roomId }) {
  useEffect(() => {
    function createOptions() {
      return { serverUrl, roomId };
    }
    const options = createOptions();
    // ...
  }, [roomId]); // roomId だけで OK
```

### 7-5. 絶対にやってはいけないこと

```tsx
// 🔴 リンタを抑制するのは最悪の手段
useEffect(() => {
  // ...
  // eslint-disable-next-line react-hooks/exhaustive-deps
}, []);
```

依存配列のリントエラーはバグのシグナル。抑制する代わりに上記のテクニックでコードを修正する。

---

## 8. 依存配列チートシート

| やりたいこと | 対応方法 |
|------------|---------|
| マウント時のみ実行 | `[]`（ただし依存値がないことを確認） |
| 特定の値が変わったとき | `[value]` に列挙 |
| state 更新で再実行ループを防ぐ | `setState(prev => ...)` の更新関数形式 |
| 最新値を読むが再実行したくない | `useEffectEvent` で分離 |
| オブジェクトが毎回変わる | プリミティブに分解して依存 |
| 関数が毎回変わる | エフェクト内に移動 or `useCallback` |
| コンポーネント外の定数 | 依存配列不要（リアクティブでない） |

---

## 9. よくある実装パターン

### データ取得（レースコンディション対策付き）

```tsx
useEffect(() => {
  let cancelled = false;

  async function fetchData() {
    const result = await fetch(`/api/data/${id}`);
    const json = await result.json();
    if (!cancelled) {
      setData(json);
    }
  }

  fetchData();
  return () => { cancelled = true; };
}, [id]);
```

### イベントリスナーの登録

```tsx
useEffect(() => {
  function handleResize() {
    setSize({ width: window.innerWidth, height: window.innerHeight });
  }
  window.addEventListener('resize', handleResize);
  return () => window.removeEventListener('resize', handleResize);
}, []); // リスナーの登録/解除は一度だけでよい
```

### タイマー

```tsx
useEffect(() => {
  const id = setInterval(() => {
    setCount(c => c + 1); // 更新関数形式で依存なし
  }, 1000);
  return () => clearInterval(id);
}, []);
```

### DOM API との同期

```tsx
function VideoPlayer({ isPlaying, src }) {
  const ref = useRef(null);

  useEffect(() => {
    if (isPlaying) {
      ref.current.play();
    } else {
      ref.current.pause();
    }
  }, [isPlaying]); // isPlaying が変わったときだけ同期

  return <video ref={ref} src={src} />;
}
```

---

## 10. 判断フローチャート

```
エフェクトを書こうとしている
        ↓
外部システムとの同期が必要？
  NO → エフェクト不要。レンダー中の計算・イベントハンドラを使う
  YES ↓
クリーンアップは必要？（接続・タイマー・リスナーなど）
  YES → return () => { cleanup() } を忘れずに
        ↓
依存配列にオブジェクト・関数が入っていないか？
  YES → プリミティブに分解 or エフェクト内に移動
        ↓
エフェクトの一部だけ最新値を読みたいが再実行したくない？
  YES → useEffectEvent で分離
        ↓
リントエラーが出ている？
  YES → リンタを抑制せず、コードを修正する
```
