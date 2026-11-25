# SYNC_SteamFX の配布 ZIP

`make_release_zip.bat` はビルド済みの Win64 Release 版 `SYNC_SteamFX.auf2` を `SYNC_SteamFX.zip` に梱包し、`SYNC_SteamFX.catalog.json` の末尾バージョンに本体の XXH3-128 を設定します。

## ZIP の作成

- Release 版 AUF2 を用意します。標準の参照先は `C:\ProgramData\aviutl2\Plugin\SYNC_SteamFX\` です。
- [xxHash v0.8.4 の Windows 版](https://github.com/Cyan4973/xxHash/releases/download/v0.8.4/xxhsum_win64_v0_8_4.zip) の `xxhsum.exe` を `Win64\Dependencies\xxHash-0.8.4\` に置くか、PATH を通します。
- 初回の正式版は `v1.0.0` です。本体の表示バージョンとカタログを合わせ、公開時に `release_date` を確認します。

```bat
setup\make_release_zip.bat
```

参照先を明示する例

```bat
setup\make_release_zip.bat -ReleaseDirectory "D:\Release\SYNC_SteamFX" -XxhsumPath "D:\Tools\xxhsum.exe"
```

## ZIP の内容

```text
SYNC_SteamFX/
  SYNC_SteamFX.auf2
  README.md
  LICENSE
  THIRD_PARTY_NOTICES.md
  ThirdParty/
    LICENSE.AviUtl2-SDK.txt
```

カタログでのインストールは、ZIP をダウンロードして展開した後に `SYNC_SteamFX` フォルダーを一括コピーします。アンインストールは `{pluginsDir}/SYNC_SteamFX` を1工程で削除します。
