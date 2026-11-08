# EasyForgeNeo AMD Companion（Windows・実験版）

**Windows Radeon PCで、ComfyUIを使わずForge Neoの画面から画像を生成するための導入補助です。** Git・Pythonの事前導入は不要です。2026年11月8日の公式情報を調査し、Forge Neoの版とAMD用PyTorchを固定しています。

これはEasyForgeNeo公式のAMD版ではありません。EasyForgeNeoはNVIDIA専用のため、そのインストーラーを呼ばず、**同じForge Neo本体を別フォルダーに導入する独立した補助パッケージ**です。EasyForgeNeoが採用する14種類の拡張は `06_InstallExtensions.bat` で追加できます。モデル一括ダウンローダー・スタイル設定は取り込みません。

**AMD実機でのUI起動・画像生成は未検証です。配布時は実験版として扱ってください。** 本パッケージの作成PCはRTX 4070 Ti SUPERです。GPU検出、GPU演算、UI起動、画像生成を別々の検証段階として記録します。

## 最短の使い方

1. ZIPを **`D:\EasyForgeNeo-AMD`** など、既存ソフトとは別の短い英数字パスへ展開します。GitHubの「Code → Download ZIP」でも構いません。バッチだけでなく、フォルダー全体が必要です。
2. `01_Detect.bat` をダブルクリック。GPU名・ドライバー・導入候補が表示されます。
3. 下の条件を確認して `02_Install.bat` を実行。通常ユーザーで実行します。導入方式と保存先が表示され、`Y`で開始します。
4. 拡張機能も使う場合は、起動前に `06_InstallExtensions.bat` を実行し、`Y`で追加します（任意）。
5. モデルを配置し、`03_Launch.bat` を実行。画面は **http://127.0.0.1:7865** に開きます。モデル未配置でもUI起動を先に試せます。
6. UIでモデルを選択して1枚生成してください。自動検証を使う場合は、起動したまま別ウィンドウで `05_TestImage.bat` を実行します。

終了は起動ウィンドウで **Ctrl+C**。次回からは `03_Launch.bat` だけです。`04_Verify.bat` はForge Neo停止中に依存関係とGPU演算を再確認します。

### 必要条件

- Windows **11 25H2、x64、ビルド26200以降**。ARM64・Windows 10・古いWindows 11では、このROCm 10.1レシピは停止します。
- AMD公式互換表に対応するドライバー：**Adrenalin 26.10.41.05**、または対応する **Windows CDE CPR 26.10.48**。これは本レシピの参照条件で、単純に数字の大きい全ドライバーの互換性を保証しません。
- ドライバーは利用者がAMDの公式配布元から導入してください。このスクリプトはドライバー・HIP SDK・OSを変更しません。WMIの`32.x`形式とAdrenalinの`26.x`形式は直接比較できないため、検出値を記録し、最終的にはGPU演算テストで確認します。
- 空き容量 **30 GB以上＋モデル分**。これはインストーラーの保守的な閾値であり、モデルの種類に応じて追加容量・RAM・VRAMが必要です。ダウンロードは数GB規模です。
- インターネット接続。GitHub、PyPI、AMD配布サーバー、Python配布先に接続します。
- インストール先は100文字以内の英数字、`-`、`_`、`.`、パス区切りのみ。空白・日本語・ネットワーク共有は避けます。導入後にフォルダーを移動しないでください。

## GPU対応と方式選択

名称だけでAMDと決めず、WindowsのPCI vendor `1002`も確認します。表は**この配布物の導入可否**であり、すべてのRadeonのAMD公式サポート範囲を表すものではありません。正確な名称リストは`manifest.json`です。同系列でも未登録名・モバイル版・OEM別名は安全側で停止します。

| GPUの例 | GPUターゲット | 本パッケージの扱い |
|---|---|---|
| RX 9070 / XT / GRE、AI PRO R9700 | gfx1201 | ROCm候補 |
| RX 9060 / XT / XT 8GB | gfx1200 | ROCm候補 |
| RX 7900 XTX / XT / GRE、PRO W7900 / W7800 | gfx1100 | ROCm候補 |
| RX 7800 XT、7700 XT / 7700、PRO W7700 / V710 | gfx1101 | ROCm候補 |
| RX 7600 / XT、7650 GRE、7400、7700S | gfx1102 | ROCm候補（個別製品の公式Windows条件も要確認） |
| RX 6950 XT / 6900 XT / 6800 XT、PRO W6800 / V620 | gfx1030 | 明示同意が必要な実験経路 |
| RX 6750 XT / 6700 XT / 6700 | gfx1031 | 同上 |
| RX 6650 XT / 6600 XT / 6600、PRO W6600 | gfx1032 | 同上 |
| RX 6500 / XT、PRO W6400 | gfx1034 | 同上。少VRAMにも注意 |
| RX 5700 / XT、5600 / XT | gfx1010 | 同上 |
| Radeon 780M | gfx1103 | 同上。共有メモリのため専用GPUと同じ容量判断は不可 |
| RX 580等のPolaris、Vega、未登録APU、型番不明 | 未確定 | 停止。別GPUに偽装しない |
| NVIDIAのみ、仮想ディスプレイ、Intelのみ | 対象外 | 停止 |

`candidate`は「導入を試せる候補」で、Forge Neoの動作認証ではありません。RDNA1/2等の`experimental`はTheRockのWindowsターゲット状況を参考にした経路で、安定版の個別GPU保証ではありません。配布wheelがない場合も停止します。自動でnightly版へ切り替えません。

複数AMD GPUではWindowsの一覧から利用GPUを選びます。導入後はHIPが列挙した**名前とgfxターゲットを再照合**し、WMIの番号をHIPの番号として流用しません。同型GPUが複数あるなど一意に決まらない場合は停止します。NVIDIAとの混在時にもCUDA版torchを入れません。

### バックエンド比較

| 方式 | 現在の確認結果 | 実装の選択 |
|---|---|---|
| ROCm / TheRock | AMD公式にWindows用PyTorchとGPU別`device-*`配布あり。NeoにHIP分岐あり | 安定版10.1.0を隔離導入。候補GPU・OS・実演算を検査 |
| DirectML | Neoには`--directml`があるが、本体に非推奨の警告。PyPIの`torch-directml 0.2.5.dev240914`はtorch 2.4.1 / torchvision 0.19.1固定 | 現行Neoとの整合する構成を確認できないため停止。古いtorchへ自動変更しない |
| ZLUDA | CUDA互換層。別プロジェクトのAMDGPU Forgeには対応があるが、それはNeoとは別物 | このNeo版で確認した専用導入経路がないため停止。DLLの上書き・別Forgeへの無断変更なし |
| WSL / Linux ROCm | 別OS環境の導入経路 | このWindowsネイティブ用バッチの対象外 |

`-Backend DirectML`や`-Backend ZLUDA`は理由を表示して終了します。実装済みの導入バックエンドはROCmです。これら3方式がすべて使える、と宣伝しないでください。

## EasyForgeNeoの拡張機能を追加する（v0.2.0）

本体の `02_Install.bat` が成功した後、Forge Neoを閉じて **`06_InstallExtensions.bat` → Y → 完了後 `03_Launch.bat`** の順に実行します。既存のNVIDIA版EasyForgeNeoからはコピーせず、それぞれの公式リポジトリから固定commitを取得します。本体と同じ `runtime\forge-neo\extensions` に配置します。

対象は次の14種類です（[EasyForgeNeo公式の拡張導入バッチ](https://github.com/hirorohi03/EasyForgeNeo/blob/4fa851def666d0ba120179b2fd3752d661936c53/EasyForgeNeo/ForgeNeo/ForgeNeoExtension.bat)と照合）。

- [--sd-webui-ar-plusplus](https://github.com/altoiddealer/--sd-webui-ar-plusplus)
- [aadetailer-neoforge](https://github.com/abzaloff/aadetailer-neoforge)
- [model-keyword](https://github.com/mix1009/model-keyword)
- [repeat-generate-4NEO](https://github.com/hirorohi03/repeat-generate-4NEO)
- [ScribeNEO](https://github.com/hirorohi03/ScribeNEO)
- [sd-dynamic-prompts](https://github.com/abzaloff/sd-dynamic-prompts)
- [sd-forge-couple](https://github.com/Haoming02/sd-forge-couple)
- [sd-webui-forge-spectrum](https://github.com/hirorohi03/sd-webui-forge-spectrum)
- [sd-webui-negpip](https://github.com/hako-mikan/sd-webui-negpip)
- [sd-webui-pnginfo-beautify](https://github.com/bluelovers/sd-webui-pnginfo-beautify)
- [sd-webui-prompt-all-in-one-neo](https://github.com/eduardoabreu81/sd-webui-prompt-all-in-one-neo)
- [sd-webui-tagcomplete-neo](https://github.com/eduardoabreu81/sd-webui-tagcomplete-neo)
- [Stable-Diffusion-Webui-Civitai-Helper-RED-UPDATE](https://github.com/Replactionap/Stable-Diffusion-Webui-Civitai-Helper-RED-UPDATE)
- [z-tipo-extension](https://github.com/KohakuBlueleaf/z-tipo-extension)

**導入できることと、AMD上で全機能が動作することは別です。拡張を含むUI・画像生成は実機未検証です。**

- 既存のtorch・torchvisionと本体パッケージを固定し、依存関係の事前チェックが通った場合に追加します。上流の `install.py` は実行しません。導入後は依存チェックとAMD GPU演算を再確認してから有効化します。
- 失敗時は追加拡張を有効化しません。原因を解消して `06_InstallExtensions.bat` を再実行できます。ダウンロード途中のファイルは `runtime\temp` に残ります。既存の手動導入拡張は上書きせず停止します。
- 正常導入後の `03_Launch.bat` は追加拡張を読み込みます。起動に問題があれば **`07_LaunchSafe.bat`** を使ってください（拡張を削除せず、一時的に無効化）。UIのExtensionsから個別に無効化することもできます。
- `model-keyword` はEasyForgeNeoに合わせて初期状態では無効です。必要ならUIのExtensionsから有効にできます。既存の他の設定・無効化リストは保持します。
- TagCompleteの追加日本語辞書、EasyForgeNeo独自プリセット・Civitai Helperへの追加パッチ、モデル本体は自動導入しません。タグ補完は拡張に同梱の辞書を使えます。
- ScribeNEOのLLM機能には別途Ollama・LM Studio等の接続設定が必要です。Prompt All-in-OneのAmazon/Alibaba翻訳SDKは依存互換性を固定できないため含めません。他の翻訳機能もサービス設定・認証・JavaScript実行環境などが必要な場合があります。
- TIPOの `tipo-kgen` は導入しますが、`llama-cpp-python` の自動導入は無効にします。GGUF方式はこの配布物の対象外です。非GGUF方式もモデル取得・追加メモリが必要で、AMD実機未検証です。
- AADetailerの検出モデルなど、拡張の初回利用時に追加ダウンロードが発生することがあります。MediaPipeを含め各方式の実動作は未検証です。
- 拡張の版と追加パッケージは `extensions.json` / `requirements-extensions.txt` に固定しています。UIから一括更新すると検証した組み合わせから外れます。拡張の更新は新しい配布版・別フォルダーで試してください。

### v0.1.0をすでに導入した場合

Forge Neoを終了し、新しいZIPのバッチ・`scripts`・JSON・requirements・説明書を、AMD版の同じフォルダーに上書きしてください。**`runtime` と `logs` は残し、`02_Install.bat` は再実行せず `06_InstallExtensions.bat` を実行します。** 本体レシピは変更していないため、AMD版の導入済み環境に追加できます。これはNVIDIA版EasyForgeNeoへの上書き対応ではありません。

## モデルを置いて生成する

モデルは同梱・自動ダウンロードしません。利用するモデルのライセンスと配布元を確認してください。まず通常のSD 1.5/SDXLチェックポイントで基本動作を確かめるか、目的のAnimaモデル一式を用意します。

| ファイル | 配置先（このパッケージ内） |
|---|---|
| Diffusion/checkpoint `.safetensors` | `runtime\forge-neo\models\Stable-diffusion` |
| Text encoder | `runtime\forge-neo\models\text_encoder` |
| VAE | `runtime\forge-neo\models\VAE` |
| LoRA | `runtime\forge-neo\models\Lora` |

必要に応じてフォルダーを作成します。Animaの種類によって必要なencoder/VAEが異なるため、[Forge Neo公式モデル案内](https://github.com/Haoming02/sd-webui-forge-classic/wiki/Download-Models)とモデル配布元の組み合わせに従ってください。通常のSDXLチェックポイントを使う場合、専用の分離Text encoderが不要なものもあります。

既存NVIDIA環境のモデルを使う場合は、必要なファイルを**コピー**してください。ジャンクション・シンボリックリンクは拒否します。既存の設定や拡張フォルダーをコピーしないでください。

起動後、モデル一覧を更新してcheckpoint、必要なencoder/VAEを選びます。初回は512×512、batch 1、Hiresなしで試し、成功後に解像度を上げます。これは疎通テストの設定であり、Animaの画質評価用設定ではありません。FP8/INT8・特殊attention・学習用途・動画・全拡張の互換性は未検証です。

`05_TestImage.bat`は現在選択中のモデルで、512×512・Euler・4 stepsのリンゴ画像を1枚要求します。自環境の起動プロセスとポートを確認し、PNGの解読・寸法・一色でないことを検査します。保存先は`runtime\verification`です。API成功や非黒画像だけでは画質や全機能を保証できないため、画像も目視してください。タイムアウトは30分です。タイムアウト時に再実行する前に、UIのInterruptで前の生成を停止してください。

## 何を変更するか

- 新規の`runtime`配下に、ポータブルMinGit、uv、専用Python、venv、Forge Neo、キャッシュを作成します。
- 本体は`4f4284b02a5c814b81c328c64ed7e99a139f21ef`、Pythonは`3.13.15`、torchは`2.14.0+rocm10.1.0`、torchvisionは`0.29.0a0+rocm10.1.0`。更新時も自動で最新版を追いません。
- uv/MinGit ZIPは固定SHA256を検査。本体は固定commitを取得・照合します。pipの通信はHTTPSですが、**全Python wheelのハッシュ固定までは実施していません**。
- PythonのPATH登録・Windowsレジストリ登録を無効にします。システムのPython、既存venv、NVIDIA環境、HIP SDK、ドライバーを書き換えません。
- 子プロセス用の環境変数を設定し、他環境のtorch/venv指定を引き継がないようにします。永続的なPATHや実行ポリシーは変更しません。バッチの`ExecutionPolicy Bypass`はそのPowerShellプロセス限りです。
- フォルダーの所有マーカーと位置を確認し、既存`runtime`への再インストールを拒否します。自動削除・`git reset --hard`はありません。
- 起動時に本家の依存関係再インストールを無効にし、CUDA版torchへの置換を防ぎます。Sage/Flash/xformersは使用せず、追加拡張は導入が完了した後に有効にします。`07_LaunchSafe.bat` では追加拡張を無効にして起動できます。外部公開せずlocalhostのみで待ち受けます。

### 依存関係の調整

調査時点のNeoは`Pillow==13.0.0`を指定しますが、同じ本体が導入する`gradio==4.40.0`の依存条件は`Pillow<11`です。また`pillow-heif==1.8.1`には`Pillow>=11.1.0`が必要で、全体を一括解決すると競合します。

本パッケージは**Pillow 10.4.0 / pillow-heif 0.20.0**に調整し、Windows Python 3.13で全依存の解決が通った組み合わせを`requirements-amd.txt`に固定しました。本体ファイルは変更しません。この調整の実際のUI・画像形式処理は未検証です。`pip check`を無視して成功扱いにはしません。

## ログと失敗時の対応

各実行ログは`logs`、GPU一覧は`logs\gpu-inventory.json`。導入済み版は`runtime\installed-packages.txt`、GPU演算結果は`runtime\gpu-verification.json`です。ログにはユーザー名を含むパス・デバイスID等が入り得るため、公開前に確認してください。環境変数や認証情報を一括出力する機能はありません。

| 表示・症状 | 対応 |
|---|---|
| GPU不明 / 対象外 | 型番、Windows版、GPU一覧を確認。Intel/仮想画面をAMDとして選ばない。未登録名はIssueで報告 |
| OS条件不一致 | 対応OS・AMD公式資料を確認。このバッチでOSを更新しない |
| `runtime already exists` | 成功済みならLaunch。途中失敗なら新しい別フォルダーにZIPを展開して再試行。元フォルダーを自動削除しない |
| SHA256 mismatch | 実行しない。表示されたダウンロードZIPだけを確認・再取得。配布元の変更も調査 |
| ダウンロード・TLS失敗 | 通信、空き容量、プロキシを確認。証明書検証やセキュリティ機能を無効にしない |
| No matching distribution / 解決不能 | `manifest.json`の組み合わせが配布中か確認。nightlyやCUDAに勝手に切り替えない |
| HIP DLL load / device unavailable | AMDドライバーの適合、再起動、GPU型番を確認。システムDLLを置換しない |
| `no kernel image` / gfx不一致 | GPUターゲット非対応。`HSA_OVERRIDE_GFX_VERSION`で偽装しない |
| GPU演算は成功、UI失敗 | `Launch-*.log`を確認。依存APIやNeoのWindows HIP互換性の問題の可能性。生成成功とは区別 |
| アドレス使用中 | 別アプリを終了するか、以下の`-Port`を使用。既存プロセスは勝手に終了しない |
| VRAM不足 / 黒画像 | batch 1・低解像度・Hiresなしで再確認。モデルの対応精度とVAE/encoderの組み合わせを確認 |
| モデルが見えない | 配置先、モデル形式、UIの更新ボタンを確認 |
| 同時操作のロック | 起動中はInstall/Verify/Detectを閉じてから実行。TestImageのみ起動中に別途実行可能。残った`.lock`ファイル自体は異常ではなく、OSのファイルロックを利用 |

アンインストールはForge Neoを終了し、必要なモデル・画像・ログを退避してから**このパッケージを展開したフォルダーだけ**をエクスプローラーで削除します。更新も新しいフォルダーへの新規導入です。既存環境の上書き更新機能は設けていません。

## コマンド指定（任意）

```powershell
# 検出のみ（ソフトのダウンロードなし）
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Manage.ps1 -Action Detect
# 表示されたWindows側GPU番号を指定
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Manage.ps1 -Action Install -Backend ROCm -GpuIndex 1
# 実験GPUでの非対話実行。これ自体が実験経路とダウンロードへの明示同意です
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Manage.ps1 -Action Install -GpuIndex 1 -Experimental -NonInteractive
# 別ポート。TestImage側にも同じポートを指定してください
.\03_Launch.bat -Port 7866
.\05_TestImage.bat -Port 7866
```

非対話実行では失敗時の終了コードは1です。バッチはメッセージ確認のため最後にpauseします。CIや自動化ではPowerShellスクリプトを直接呼んでください。

## GitHub配布と検証

[配布ZIP（Releases）](https://github.com/asugonomi/easyforgeneo-amd/releases)から取得してください。新規導入専用の実験版です。既存EasyForgeNeoへの上書き・移行や、公式のNVIDIA向け更新バッチとの併用には対応しません。`runtime`・`logs`・生成画像はコミットしないでください。検証用GitHub Actionsを同梱しています。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Safety.ps1
python -m unittest discover -s tests -v
```

実施済み・未実施の境界は[VALIDATION.md](VALIDATION.md)。調査元と固定版は[SOURCES.md](SOURCES.md)。本パッケージの独自コードはMIT、ダウンロードするForge NeoはAGPL-3.0で、他の構成物にもそれぞれのライセンスが適用されます。
