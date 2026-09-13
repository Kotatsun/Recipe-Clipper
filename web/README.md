# RecipeClipper Web / PWA

既存のSwiftUI版RecipeClipperをsource of truthとして移行する、local-firstのWeb版です。アプリ本体はブラウザのIndexedDBに保存され、サーバーDB・ログイン・常設バックエンドを必要としません。

## 既存iOS版の解析結果

- SwiftUI + SwiftData。`RecipeClipping/RecipeClippingApp.swift` が `Recipe` と `CookLog` のModelContainerを作成します。
- `Recipe` は `Models.swift` の次の値を持ちます。
  - ID、タイトル、概要、元URL、ホスト、元画像URL、ローカル画像ファイル名
  - メモ、タグ、分量、材料行、手順行、材料チェック状態
  - 正規化URL、登録元種別、お気に入り、評価、また作りたい
  - 抽出本文、取得本文/HTML、取得元、抽出信頼度/警告、材料/手順の抽出元
  - 作成日時、更新日時、`CookLog` の配列
- `CookLog` はID、調理日、メモ、画像ファイル名、評価、次回改善メモ、アレンジメモを持ちます。
- SwiftDataストア本体はアプリのApplication Support配下に保存され、画像は `Documents/RecipeImages` に保存されます。`ImageStore.swift` が画像の縮小・読み出しを担当します。
- 現行版にはすでに、右上の「…」からレシピ、CookLog、タグ、材料/手順、状態、日時、画像を含むZIPバックアップを書き出す機能があります。したがって、旧iOS版に再入力用機能を追加せず、その既存ZIPを移行入力に使います。
- 主要UXは、レシピ一覧、検索、フィルタ、タグ絞り込み、並び替え、詳細、材料チェック、編集、新規追加、CookLog、PDF/テキスト共有、バックアップ/復元です。Web版ではこのうち個人利用に必要な一覧・詳細・編集・追加・検索・絞り込み・材料チェック・CookLog・Backup/Restoreを維持し、iOSのShare ExtensionとPDF生成は今回のスコープ外にしました。

## 採用した移行経路

```text
iOS SwiftData
  ↓ 既存の「バックアップを書き出し」
RecipeClipper-Backup-YYYY-MM-DD.zip
  ├─ backup.json
  └─ RecipeImages/*
  ↓ Web版の検証付きImport
IndexedDB (recipes / images)
```

`backup.json` は既存iOS版のフィールド名（`sourceURL`, `ingredients`, `instructions`, `cookLogs` など）を維持しています。Web版の書き出しには、将来の実装を判定できる `format: "recipeclipper"` と `schemaVersion: 1` を加えます。旧iOS版の `formatVersion: 1/2` バックアップも読み込めます。

### データを失わないための設計

- レシピID、CookLog ID、ISO-8601日時、タグ、材料/手順の配列順を保持します。
- 既知フィールド以外のJSONキーも `_unknownFields` として保持し、次回エクスポートに戻します。
- Import前にJSON、ID重複、日付、配列、schemaVersion、画像参照を検証します。
- Importは検証後にのみ実行し、既存IndexedDBを同じID単位で置き換えます。同じバックアップを2回読み込んでも重複しません。
- Import後、portable JSONへ再シリアライズして再読込し、件数、ID、全既知フィールド、配列順、CookLogを比較するsemantic equivalence検証を行います。
- Service Workerのcacheはapp shellだけに使い、レシピデータはIndexedDBだけに保存します。

## iPhoneから実際に移行する手順

1. まず既存iPhoneアプリを削除せずに開き、レシピ一覧が表示されることを確認します。
2. 右上の `…` → `バックアップを書き出し` を選び、`RecipeClipper-Backup-YYYY-MM-DD.zip` をFilesのiCloud Drive等へ保存します。画像も同じZIPに含まれます。
3. Web版URLをiPhoneのSafariで開き、共有メニューから「ホーム画面に追加」します。以後はPWAとして起動できます。
4. Web版で `⚙` → `バックアップを読み込む` を選び、手順2のZIPを選びます。
5. 「復元前の検証結果」でレシピ件数、CookLog件数、タグ数、ID保持、画像警告、semantic equivalenceが問題ないことを確認します。
6. `この内容で上書き復元` を押します。現在のWeb版データを置き換える操作なので、既存Webデータがある場合は先にWeb版バックアップを書き出してください。
7. 復元後、代表画像、材料、手順、材料チェック、CookLogを代表数件確認し、`移行データを点検` → `現在のデータを検証する` を実行します。
8. Web版の `バックアップを書き出す` でportable ZIPをもう一度保存します。新しいiPhoneや別ブラウザでは、そのZIPを同じ手順で読み込めます。

## ローカル確認

ビルドツールやNode.jsに依存しない静的サイトです。リポジトリルートで次のように確認できます。

```bash
python3 -m http.server 4173 --directory web
```

ブラウザで [http://localhost:4173/](http://localhost:4173/) を開きます。Service Workerのオフライン確認にはlocalhostを使ってください。

移行テストは [http://localhost:4173/tests/migration.test.html](http://localhost:4173/tests/migration.test.html) で実行できます。`tests/native-backup-v2.json` は現行Swiftの`BackupService`フィールドを元にしたfixtureで、未知フィールド保持、ID/日時/配列順、重複ID拒否、Web export→再importの意味同値を確認します。

## GitHub Pages

`.github/workflows/deploy-pages.yml` は `web/` をそのまま静的アーティファクトとしてGitHub Pagesへデプロイします。

1. GitHub repository Settings → Pages → SourceをGitHub Actionsにします。
2. `main` に `web/` の変更をpushするか、Actionsから `Deploy RecipeClipper Web` を手動実行します。
3. 表示されたPages URLをSafariで開きます。将来hostを変える場合も、source codeとportable ZIPがあれば復元できます。

## 既存iOS版について

旧iOSアプリは移行確認が終わるまで削除しないでください。今回の変更は既存ZIPが新しいWeb portable metadata (`format`, `schemaVersion`) を持てるようにする加算的な変更だけで、SwiftDataの保存フィールドや `Documents/RecipeImages` の場所は変更していません。旧形式のバックアップも引き続き復元できます。
