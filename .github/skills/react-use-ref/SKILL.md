---
name: react-use-ref
description: >
  React の useRef フック・DOM ref・ref コールバック・useImperativeHandle・flushSync の
  正しい使い方・アンチパターン・ベストプラクティスを、公式ドキュメント（ja.react.dev）に基づいて解説するスキル。
  ref を使う前の判断・DOM 操作・子コンポーネントへの ref 転送に使用する。
sources:
  - https://ja.react.dev/learn/referencing-values-with-refs
  - https://ja.react.dev/learn/manipulating-the-dom-with-refs
react_version: "19.x"
---

# React useRef / ref — 完全ガイド（公式ドキュメントベース）

## 0. 最初に問うべき質問

ref を使おうとしたら、まず自問する：

> **「この値は画面に表示される（レンダーに影響する）か？」**

- **YES → `useState`** を使う。表示内容は state で管理する。
- **NO → `useRef`** を使う。レンダーに影響しない値の保持・DOM 操作に使う。

ref は「React の外に踏み出す」ための避難ハッチ。頻繁には必要ない。

---

## 1. useRef とは何か

### 基本構文

```tsx
import { useRef } from 'react';

const ref = useRef(initialValue);
// 返り値: { current: initialValue }
```

`ref.current` は：
- **ミュータブル**（直接書き換えられる）
- **変更しても再レンダーを起こさない**
- レンダー間で値が保持される
- React が管理しない「コンポーネントの秘密のポケット」

### ref と state の比較

| 特性 | `useRef` | `useState` |
|------|----------|------------|
| 変更時の再レンダー | **起きない** | 起きる |
| 値の変更方法 | `ref.current = newValue` で直接書き換え | セッタ関数（`setValue`）経由のみ |
| レンダー中に読み取れるか | ❌ 非推奨（値が不安定になる） | ✅ 安全 |
| 用途 | DOM ノード・タイマー ID・外部 API | 表示する値・UI の状態 |

---

## 2. ref を使うべきシーン

公式が挙げる典型的なユースケース：

1. **DOM 要素への参照**（フォーカス・スクロール・サイズ計測）
2. **タイマー ID の保存**（`setInterval` / `setTimeout` の返り値）
3. **レンダーに使わないその他の値**（前回の props の保存など）

```tsx
// ✅ タイマー ID を ref で保持（レンダーには使わない）
const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

function handleStart() {
  intervalRef.current = setInterval(() => {
    setNow(Date.now());
  }, 10);
}

function handleStop() {
  clearInterval(intervalRef.current);
}
```

---

## 3. DOM ref の基本パターン

### 3-1. 単一 DOM ノードへの ref

```tsx
import { useRef } from 'react';

function Form() {
  const inputRef = useRef<HTMLInputElement>(null);

  function handleClick() {
    // イベントハンドラ内でのみアクセスする
    inputRef.current?.focus();
  }

  return (
    <>
      <input ref={inputRef} />
      <button onClick={handleClick}>Focus</button>
    </>
  );
}
```

**手順：**
1. `useRef(null)` で ref を宣言
2. JSX の `ref` 属性に渡す（`<input ref={inputRef} />`）
3. React がコミット後に `ref.current` に DOM ノードをセット
4. イベントハンドラやエフェクト内から `ref.current` にアクセスして操作

### 3-2. スクロール操作

```tsx
function Carousel() {
  const firstRef = useRef<HTMLImageElement>(null);
  const secondRef = useRef<HTMLImageElement>(null);

  function scrollToFirst() {
    firstRef.current?.scrollIntoView({
      behavior: 'smooth',
      block: 'nearest',
      inline: 'center',
    });
  }

  return (
    <>
      <button onClick={scrollToFirst}>First</button>
      <img ref={firstRef} src="..." />
      <img ref={secondRef} src="..." />
    </>
  );
}
```

---

## 4. 動的リストの ref — ref コールバック

`map()` の中で `useRef` を呼び出すことは**できない**（フックのルール違反）。

```tsx
// ❌ 動作しない
{items.map(item => {
  const ref = useRef(null); // フックはトップレベルのみ
  return <li ref={ref} />;
})}
```

### 解決策：ref コールバック + Map

```tsx
function List({ items }: { items: { id: number; name: string }[] }) {
  // ref の値として Map を保持する
  const itemsRef = useRef<Map<number, HTMLLIElement> | null>(null);

  function getMap() {
    if (!itemsRef.current) {
      itemsRef.current = new Map();
    }
    return itemsRef.current;
  }

  function scrollToItem(id: number) {
    const node = getMap().get(id);
    node?.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  }

  return (
    <ul>
      {items.map(item => (
        <li
          key={item.id}
          ref={node => {
            const map = getMap();
            if (node) {
              map.set(item.id, node);   // マウント時：登録
            } else {
              map.delete(item.id);       // アンマウント時：削除
            }
            // React 19 スタイル（クリーンアップ関数を return）
            // return () => { map.delete(item.id); };
          }}
        >
          {item.name}
        </li>
      ))}
    </ul>
  );
}
```

**ポイント：**
- `ref` 属性に**関数**を渡すのが「ref コールバック」
- DOM マウント時：ノードを引数に呼ばれる
- DOM アンマウント時：`null` を引数に呼ばれる（または返したクリーンアップ関数が実行される）
- Strict Mode では開発環境で 2 回呼ばれる（バグ検出のための仕様）

---

## 5. 子コンポーネントへの ref の受け渡し（React 19）

React 19 では、関数コンポーネントは `ref` を**通常の props として**受け取れる（`forwardRef` 不要）。

```tsx
// ✅ React 19 — ref は普通の props
function MyInput({ ref, ...props }: React.ComponentProps<'input'>) {
  return <input ref={ref} {...props} />;
}

function Form() {
  const inputRef = useRef<HTMLInputElement>(null);

  return (
    <>
      <MyInput ref={inputRef} />
      <button onClick={() => inputRef.current?.focus()}>
        Focus
      </button>
    </>
  );
}
```

> **React 18 以前との互換性が必要な場合**は `forwardRef` を使う（レガシー API）。

---

## 6. useImperativeHandle — 公開 API を絞る

子コンポーネントの DOM ノードを丸ごと親に渡すと、親が何でもできてしまう。
公開したいメソッドだけを持つカスタムオブジェクトを渡すには `useImperativeHandle` を使う。

```tsx
import { useRef, useImperativeHandle } from 'react';

type InputHandle = { focus: () => void };

function MyInput({ ref }: { ref: React.Ref<InputHandle> }) {
  const realInputRef = useRef<HTMLInputElement>(null);

  // 親に渡す ref の値をカスタムオブジェクトに差し替える
  useImperativeHandle(ref, () => ({
    focus() {
      realInputRef.current?.focus();
    },
    // DOM ノード全体は渡さない → CSS 変更などは親からできない
  }));

  return <input ref={realInputRef} />;
}

function Form() {
  const inputRef = useRef<InputHandle>(null);

  return (
    <>
      <MyInput ref={inputRef} />
      <button onClick={() => inputRef.current?.focus()}>Focus</button>
    </>
  );
}
```

**使うタイミング：**
- ライブラリコンポーネントや汎用 UI コンポーネントで、外部から呼べる操作を意図的に制限したいとき
- DOM ノードの直接参照を外部に漏らしたくないとき

---

## 7. ref がセットされるタイミング

React の更新は 2 フェーズ：

```
レンダー（コンポーネント関数の実行）
    ↓  DOM はまだ更新されていない → ref.current はまだ古い値 or null
コミット（DOM への変更反映）
    ↓  影響を受ける ref.current を一旦 null にリセット
    ↓  DOM 更新
    ↓  ref.current に新しい DOM ノードをセット
    ↓  エフェクト実行
```

**結論：**
- **レンダー中に `ref.current` を読み書きしない**（値が不安定）
- ref にアクセスするのは**イベントハンドラ**か**エフェクト内**
- アンマウント時、React は `ref.current` を `null` に戻す

---

## 8. flushSync — state 更新直後に DOM を操作したい

React の state 更新は非同期にバッチ処理される。そのため、`setState` の直後に DOM を操作しても、DOM がまだ更新されていない場合がある。

```tsx
// ❌ 問題：scrollIntoView の時点で新しい todo がまだ DOM にない
function handleAdd() {
  setTodos([...todos, newTodo]);
  listRef.current.lastChild.scrollIntoView(); // 1つ前の要素にスクロールされる
}

// ✅ 解決：flushSync で DOM 更新を同期的に強制
import { flushSync } from 'react-dom';

function handleAdd() {
  flushSync(() => {
    setTodos([...todos, newTodo]); // この中の state 更新が即座に DOM に反映される
  });
  listRef.current.lastChild.scrollIntoView({ behavior: 'smooth' });
}
```

**注意：** `flushSync` はパフォーマンスに影響する。「state 更新直後の DOM に即アクセスしたい」という限定的な場面にのみ使う。

---

## 9. React 管理 DOM の書き換えは危険

ref で取得した DOM ノードを React の管理外で書き換えると、React の内部状態と DOM が不整合になりクラッシュする。

```tsx
// ❌ 危険：React が管理する DOM を直接削除する
ref.current.remove(); // その後 setState で再表示しようとするとクラッシュ

// ✅ 安全：React の state で表示を制御する
const [show, setShow] = useState(true);
return show ? <p ref={ref}>Hello</p> : null;
```

**安全な DOM 操作の指針：**

| 操作の種類 | 安否 | 備考 |
|-----------|------|------|
| `focus()` / `blur()` | ✅ 安全 | DOM 構造を変えない |
| `scrollIntoView()` | ✅ 安全 | DOM 構造を変えない |
| サイズ・位置の計測（`getBoundingClientRect` など） | ✅ 安全 | 読み取りのみ |
| React が管理しない空コンテナへの追加 | ✅ 安全 | React が触れない領域 |
| React が管理するノードの追加・削除 | ❌ 危険 | React との競合・クラッシュ |
| React が管理するノードのスタイル直接書き換え | ⚠️ 要注意 | 次のレンダーで上書きされる |

---

## 10. TypeScript での型付け

```tsx
// DOM 要素の型を指定（初期値は null）
const inputRef = useRef<HTMLInputElement>(null);
const divRef = useRef<HTMLDivElement>(null);
const videoRef = useRef<HTMLVideoElement>(null);
const canvasRef = useRef<HTMLCanvasElement>(null);

// 非 DOM 値の ref（null にならない場合は型を広げる）
const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);
const instanceRef = useRef<ThirdPartyLib | null>(null);

// useImperativeHandle のカスタム型
type MyHandle = { focus: () => void; reset: () => void };
const customRef = useRef<MyHandle>(null);
```

---

## 11. よくある実装パターン

### マウント時に自動フォーカス

```tsx
function SearchBox() {
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    inputRef.current?.focus();
  }, []); // マウント時のみ

  return <input ref={inputRef} placeholder="Search..." />;
}
```

### 前回の props/state を記憶する

```tsx
function Component({ value }: { value: number }) {
  const prevValueRef = useRef(value);

  useEffect(() => {
    prevValueRef.current = value; // コミット後に更新
  });

  const prevValue = prevValueRef.current; // レンダー時点では前回の値

  return <p>前回: {prevValue} → 今回: {value}</p>;
}
```

### メディア要素の制御（useEffect と組み合わせ）

```tsx
function VideoPlayer({ isPlaying, src }: { isPlaying: boolean; src: string }) {
  const videoRef = useRef<HTMLVideoElement>(null);

  useEffect(() => {
    if (isPlaying) {
      videoRef.current?.play();
    } else {
      videoRef.current?.pause();
    }
  }, [isPlaying]);

  return <video ref={videoRef} src={src} />;
}
```

### 外部ライブラリとの統合（マップ・チャートなど）

```tsx
function MapWidget({ center }: { center: [number, number] }) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<ThirdPartyMap | null>(null);

  useEffect(() => {
    // マウント時に外部ライブラリのインスタンスを作成
    mapRef.current = new ThirdPartyMap(containerRef.current!, { center });
    return () => {
      mapRef.current?.destroy(); // クリーンアップ
      mapRef.current = null;
    };
  }, []); // インスタンス生成は 1 回のみ

  useEffect(() => {
    mapRef.current?.setCenter(center); // center 変化時だけ同期
  }, [center]);

  return <div ref={containerRef} style={{ height: 400 }} />;
}
```

---

## 12. 判断フローチャート

```
値を保持・操作したい
    ↓
画面の表示に影響する？
  YES → useState を使う
  NO  ↓
DOM ノードにアクセスしたい？
  YES → useRef(null) + JSX の ref 属性
         ↓
         動的なリスト（数が可変）？
           YES → ref コールバック + Map パターン
           NO  → useRef で単一 ref
         ↓
         子コンポーネントの DOM？
           → props として ref を渡す（React 19）
               ↓
               公開 API を絞りたい？
                 YES → useImperativeHandle
                 NO  → DOM を直接渡す
  NO  ↓
タイマー ID / 外部インスタンス / 前回の値など
  → useRef で保持
      ↓
      state 更新直後に DOM を操作する必要がある？
        YES → flushSync でラップ
      ↓
      レンダー中に ref.current を読んでいないか確認
      （読む必要があるなら state を使う）
```

---

## 13. ベストプラクティス まとめ

- **ref は避難ハッチ**。アプリのロジックの大半が ref に依存しているなら設計を見直す
- **レンダー中に `ref.current` を読み書きしない**（唯一の例外：初回レンダーで一度だけ初期化する `if (!ref.current) ref.current = new Thing()`）
- ref へのアクセスは**イベントハンドラかエフェクト内**に限定する
- **React 管理 DOM の追加・削除・書き換えは避ける**（競合・クラッシュの原因）
- フォーカス・スクロール・サイズ計測など**非破壊的な操作に留める**
- `useImperativeHandle` で**子コンポーネントの公開 API を意図的に制限**する
- 動的リストへの ref には**ref コールバック + Map** パターンを使う
- state 更新直後に DOM 操作が必要な稀なケースでは **`flushSync`** を使う
