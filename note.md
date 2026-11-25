# SYNC_SteamFX 作業ノート

- 本番は `SYNC_SteamFX.dproj` / `SYNC_SteamFX.auf2` の1つ。Delphi 37.0 の IDE では dproj を直接開く。
- 現行仕様は `docs/SPECIFICATION.md`、操作は `README.md` を参照する。
- `SYNC_WeatherFX/note.md` から Win64 ビルドと配置、SDK とライセンス、ソース配置、文字コード、本番 AUF2 を使う検査の手順を引き継いだ。
- 新しいプロジェクト GUID を発行した。参考元のデバッガーホスト `D:\aviutl2_v2.1.16\aviutl2.exe` を両構成に設定した。通常の検査はコマンドラインで行う。
- `setup` は SYNC_WeatherFX から継承した配布用フォルダーで、SteamFX の正式初版 `v1.0.0` に対応する。操作は `setup/README.md` を参照する。
- `Source/Lib` は SDK と登録処理。型は公式ヘッダーと照合し、過去フレームのトラック取得とシェーダー呼び出しの宣言を追加した。ホストのハンドル・ポインターはコールバック内だけで借用する。
- `Source/Plugin/Filter` は SDK の入出力と項目登録、`Source/Common` は設定・プリセット・湯気の軌道と着色。ユニットは dpr の `in` と dproj の `DCCReference` の両方に登録する。
- 日本語を含む Pascal と Windows PowerShell のソースは UTF-8 BOM 付き、CRLF。ユニットの先頭に責務、公開処理には入力、出力、必要な所有権を記す。

## ビルド

```powershell
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild SYNC_SteamFX.dproj /t:Rebuild /p:Config=Debug /p:Platform=Win64'
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild SYNC_SteamFX.dproj /t:Rebuild /p:Config=Release /p:Platform=Win64'
```

各構成の警告・エラーを確認し、最後に Release を配置する。DCU は `Win64/Debug/DCU` と `Win64/Release/DCU`、AUF2 は `C:\ProgramData\aviutl2\Plugin\SYNC_SteamFX\SYNC_SteamFX.auf2` に出力する。ビルド後イベントは同じフォルダーで DLL を AUF2 にコピーし、元の DLL と Release の RSM を削除する。

## 描画と時間軸

画像入力としてシーンサイズを確保し、画像の中心を基準に「発生源配置」の発生位置X・Y（初期値 0、正方向は右・下）を加えて湯気を生成する。プリセットは発生位置を保持する。画像全体の X・Y・Z、拡大率、透明度は基底オブジェクトの標準描画で扱う。湯気内部の疑似立体投影には傾斜角度・回転角度・遠近感・奥行を使用する。発生量は出生時刻のトラック値を参照する。連続放出は配置の先頭で初期の発生量から湯気が立ち上った状態を生成する。周期・ランダム・瞬間放出は配置の先頭から評価する。描画中に過去のフレームを保存しないため、逆シークでも同じ条件から同じ湯気を再構築する。

D3D11 のピクセルシェーダーで濃淡を生成し、透過画像を直接書き込む。シェーダーを実行できない場合は CPU で同じ密度分布を描画する。過去のトラック値の取得に失敗した時点には現在の発生量を使う。

## 検査

```powershell
.\Tests\run_tests.ps1
```

本番 AUF2 を読み込む検査用 EXE で、4 エクスポート、SDK のフィールド位置、初期値、全32プリセット、基本設定の重複がないこと、ホスト画像パラメータの保持、設定反映失敗時の復元、時刻の逆シーク、発生量ゼロ後の消失、発生量による変化、瞬間放出と白い息を検査した。D3D11 ハードウェア上で本体のシェーダーを実行し、CPU との画素差、GPU 実行失敗時の切り替えと 1920×1080 の滞留描画を確認した。

正式初版 `v1.0.0` の Win64 Debug / Release の Rebuild は各構成で警告0・エラー0。本番 AUF2 の検査で表示バージョンを確認し、描画検査の PNG は33枚すべてが構成間で SHA-256 一致。ビルド・検査の生成物は整理し、検査用 EXE と PNG は上記の検査スクリプトで再生成できる。配置した Release の AUF2 は 1,696,256 バイト、SHA-256 は `B0F1E3C400FEBA111E3FE202E2D1F273936C71CD2A55E62F364266BE605D0C5A`。

今回の動作検査では検査用 EXE から本番のコールバックを実行した。AviUtl2 上のメニュー表示とタイムライン操作、Delphi IDE 内での表示は未確認。

## 正式初版の配布準備（2026-11-24）

- `setup/make_release_zip.bat` で `setup/SYNC_SteamFX.zip` と `setup/SYNC_SteamFX.catalog.json` を作成した。Git リモートに合わせて配布元を `vramwiz/SYNC_SteamFX` とし、カタログの `release_date` に準備日 `2026-11-24` を設定した。
- カタログは ZIP の取得・展開後に `{tmp}/SYNC_SteamFX` を `{pluginsDir}/SYNC_SteamFX` に一括コピーする。アンインストールの `delete` は同じフォルダーを対象に1件だけ登録する。
- ZIP の5ファイルを元ファイルとバイト照合し、AUF2 の XXH3-128 `b007abf0415e357160d2f1922c76105f` がカタログと一致することを確認した。バッチの新規作成と既存 ZIP の置換を実行し、同じ入力から同じ ZIP・JSON が得られることを確認した。カタログアプリの画面操作は未確認。
- `Win64/Dependencies/xxHash-0.8.4/xxhsum.exe` は既存の同版を使用した。SHA-256 は `2B61362A094F4D889D18EE9978605DEC10B188E55B56E86AD4ED0B3074F6F797`。

## 発生位置 X・Y の追加（2026-11-25）

- 「発生源配置」に発生位置X・Y を追加した。各軸の範囲は -8192～8192 px、設定単位は 1 px。
- Win64 Debug / Release の Rebuild は警告0・エラー0。配置先の AUF2 を構成ごとに検査用 EXE で読み込み、XY オフセット、画面外のクリップ、プリセットによる位置の保持、CPU と D3D11 の描画を確認した。X・Y が 0 の PNG は、変更前と両構成の33枚が SHA-256 で一致した。
- 最後に配置した Release の AUF2 は 1,696,768 バイト。SHA-256 は `BB96256206B9E9D0E1B378A958C8FB92D255FB4519402F98B6FB71D8688613C1`。AviUtl2 の設定画面と Delphi IDE 内の表示は未確認。
- `setup/make_release_zip.bat` で更新版 `v1.0.0` の ZIP とカタログを作成した。ZIP の5ファイルを梱包元と照合し、検査済み Win64 Release AUF2 の XXH3-128 `e6d5a337b60e659051e164481e678916` がカタログと一致することを確認した。
