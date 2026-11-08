# 検証記録

確認日：2026-11-08。検証機：Windows x64、NVIDIA GeForce RTX 4070 Ti SUPER。AMD GPUなし。

## 実施済み

- Windows PowerShell 5.1でスクリプト構文・安全性17項目が成功。GPU10ケース（NVIDIA、仮想GPU、誤った型番、未知APUを含む）、既存保存先の拒否と内容保持、不正SHA256の拒否、ジャンクション経由の書き込み拒否を検査。
- PythonのGPU選択テスト4件成功。Windows/HIPの表記差、gfx不一致、同型GPUの曖昧性、NVIDIA誤選択を検査。
- `Manage.ps1 -Action Detect`を実機で実行。仮想ディスプレイとRTX 4070 Ti SUPERをいずれも対象外と判定。検出のみでruntimeは作成されない。
- 公式uv 0.12.5 ZIPを取得し、manifestのSHA256との一致を確認。
- Python 3.13.15を作業用ディレクトリへ取得（`--no-bin --no-registry`）。既存Pythonへのインストールや登録なし。
- uvで専用venv＋pipの初期セットアップを確認。
- Windows/Python 3.13・gfx1201のAMD torch/torchvisionを含む最終依存リスト全体を、uvのresolverで解決。元のPillow/Gradio競合を再現し、Pillow/HEIF調整後に成功。
- ZIP内の収録ファイルと内容を原本と照合。実行ログ、GPU固有情報、runtime、キャッシュを配布ZIPから除外。

## 未実施（成功とみなさない項目）

- 配布バッチのAMD PC上での最初から最後までの実行。
- AMD用巨大wheel群の完全ダウンロード・インストール、実環境での`pip check`。
- HIP GPUの列挙・FP32/FP16行列積・畳み込み・attention実行。
- Forge Neo UIの起動、ブラウザー表示、AMDでのモデル読み込み・画像生成。
- Anima、SDXL、SD1.5それぞれの画質・速度・VRAMピーク・安定性。
- 調整したPillow/HEIFでの全UI/画像形式処理、追加拡張、複数AMD GPU、iGPU、各実験GPU。
- GitHub Actionsのクラウド実行（ワークフローは同梱）。

依存関係の解決成功は、wheelのインストールやGPU実行成功の代わりではありません。実機ではInstallの完了マーカーは依存検査とGPU演算の両方が通るまで書き込みません。Launchの`UI READY`とTestImageの`IMAGE SMOKE PASSED`も別の段階です。

知人のPCで確認する順序：Detect → Install → Launch → モデル配置・選択 → TestImage → 出力画像の目視。失敗時は該当ステップのログを確認してください。
