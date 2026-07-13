# RecipeClipper

個人用のiPhoneレシピ管理アプリです。7日ごとにXcodeから実機へ上書きRunして使う前提で、既存データを消さない運用を最優先にします。

## Bundle ID固定

`PRODUCT_BUNDLE_IDENTIFIER` は必ず `com.tatsuki.RecipeClipper` のまま使ってください。

この値を変更すると、iOS上では別アプリ扱いになり、既存のSwiftDataストアや `Documents/RecipeImages` の画像を引き継げません。Share Extensionは `com.tatsuki.RecipeClipper.ShareExtension` のままにします。

## 週1再ビルド手順

1. iPhoneをMacに接続する
2. Xcodeで `RecipeClipping.xcodeproj` を開く
3. Schemeはメインアプリ `RecipeClipping` を選ぶ
4. 実行先は自分の実機iPhoneを選ぶ
5. Signing & CapabilitiesでメインアプリとShare ExtensionのTeamが同じPersonal Teamになっていることを確認する
6. アプリを削除せず、XcodeのRunで上書きインストールする

アプリをホーム画面から削除すると、端末内のレシピ、画像、CookLogも削除されます。再ビルド時は必ず削除せず上書きしてください。

## バックアップ

トップ画面右上の `...` メニューから以下を使えます。

- `バックアップを書き出し`: レシピ、CookLog、タグ、材料、手順、材料チェック状態、評価、お気に入り、また作りたい、sourceURL、画像ファイル名、`Documents/RecipeImages` 配下の画像をZIPにまとめてFilesアプリへ保存
- `バックアップから復元`: ZIP内の `backup.json` と `RecipeImages` から上書き復元

復元は現在のレシピと画像をバックアップ内容で置き換えます。週1再ビルド前や大きな変更前にはバックアップを書き出してください。

## データ保持チェックリスト

上書きRun後に以下を確認してください。

- 既存レシピ一覧が表示される
- 代表画像が表示される
- レシピ詳細が開ける
- CookLogが残っている
- お気に入り、評価、また作りたいが自然な初期値で表示される
- 材料、手順、タグ、メモが編集できる
- アプリを再起動してもデータが残る
- Xcodeログに `RecipeClipper data: ... recipes, ... cook logs` が出る
- SwiftDataエラー画面が出ていない

## Share Extension確認

実機で以下から共有を確認してください。

- Safari
- Chrome
- Instagram
- YouTube

URL型で渡る場合と、plain text内にURLが入る場合の両方を受け取ります。共有からRecipeClipperを自動で開けない場合は、ExtensionがURLをクリップボードへコピーします。その場合はRecipeClipperを手動で開き、URL入力欄へ貼り付けてください。

## 実装メモ

- SwiftDataの既存フィールド名は不用意に変更しない
- 画像保存先は `Documents/RecipeImages` のまま維持する
- 新規フィールドはデフォルト値つきで追加する
- 破壊的なモデル変更が必要な場合はMigrationPlanを追加する
- Bundle IDを変更しない
