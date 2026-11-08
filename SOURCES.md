# 調査記録（2026-11-08）

一次資料と実際の公式ソースを参照しました。`latest`やmainは後日変わるため、実装は下記commitとmanifestの版を固定します。

| 資料 | 確認内容 |
|---|---|
| [EasyForgeNeo](https://github.com/hirorohi03/EasyForgeNeo/tree/4fa851def666d0ba120179b2fd3752d661936c53) | NVIDIA専用インストーラー。Python/uv・拡張・起動構成。本補助では公式バッチを実行しない |
| [Forge Neo](https://github.com/Haoming02/sd-webui-forge-classic/tree/4f4284b02a5c814b81c328c64ed7e99a139f21ef) | 取得時点のneo HEAD。本体のROCm/DirectML分岐と起動オプション |
| [memory_management.py](https://github.com/Haoming02/sd-webui-forge-classic/blob/4f4284b02a5c814b81c328c64ed7e99a139f21ef/backend/memory_management.py) | torch.version.hip、gfx判定、DirectML非推奨警告 |
| [launch_utils.py](https://github.com/Haoming02/sd-webui-forge-classic/blob/4f4284b02a5c814b81c328c64ed7e99a139f21ef/modules/launch_utils.py) | 既定CUDA torch 2.14/cu130、Gradio 4.40、起動時依存準備。AMD起動ではスキップ |
| [AMD ROCm 10.1互換表](https://rocm.docs.amd.com/en/latest/compatibility/compatibility-matrix.html) | Windows 11 25H2、Adrenalin 26.10.41.05、GPU gfx対応。本レシピのOS/driver条件 |
| [AMD PyTorch導入](https://rocm.docs.amd.com/projects/ai-ecosystem/en/latest/frameworks/pytorch/install.html) | Windows Python 3.13、stable.repo.amd.com、torch 2.14.0+rocm10.1.0 / torchvision 0.29.0a0+rocm10.1.0、GPU別extras |
| [TheRock GPU状態](https://github.com/ROCm/TheRock/blob/077b4a6ede4dac148b59db6a7e8fde6009641837/SUPPORTED_GPUS.md) | Windows RDNA系ターゲット。Build Passingだけでは実行成功を意味しない。正式互換表とは区別 |
| [TheRock型番対応表](https://github.com/ROCm/TheRock/blob/077b4a6ede4dac148b59db6a7e8fde6009641837/build_tools/hack/env_check/AMDGPU_LLVM_TARGET.py) | 採用したGPU名とgfx対応の参考。全行を無条件には採用していない |
| [TheRock配布方式](https://github.com/ROCm/TheRock/blob/077b4a6ede4dac148b59db6a7e8fde6009641837/RELEASES.md) | 安定/開発版のインデックス、device extrasの区別 |
| [旧AMD Windows 7.2.1資料](https://rocm.docs.amd.com/projects/radeon-ryzen/en/docs-7.2.1/docs/compatibility/compatibilityrad/windows/windows_compatibility.html) | Python 3.12 / torch 2.9世代。旧資料を現行の全対応表と取り違えない |
| [Microsoft DirectML](https://learn.microsoft.com/en-us/windows/ai/directml/pytorch-windows) | DirectX 12用PyTorch backend |
| [torch-directml metadata](https://pypi.org/pypi/torch-directml/json) | 0.2.5.dev240914のtorch==2.4.1、torchvision==0.19.1固定を取得時確認 |
| [ZLUDA](https://github.com/vosen/ZLUDA) | CUDA互換層。Neo専用の検証済み構成とは扱わない |
| [AMDGPU Forge](https://github.com/lshqqytiger/stable-diffusion-webui-amdgpu-forge) | DirectML/ZLUDA対応の別Forge。Neoへの同一視や自動置換はしない |
| [Gradio metadata](https://pypi.org/pypi/gradio/4.40.0/json) | Pillow<11の依存条件。Neo既定requirementsとの競合をresolverで再現 |
| [HEIF metadata](https://pypi.org/pypi/pillow-heif/0.20.0/json) | Pillow 10.4と整合する0.20.0を選択 |
| [uv release](https://github.com/astral-sh/uv/releases/tag/0.12.5) | Windows ZIPとGitHub release APIのSHA256を照合、実ダウンロードでも一致 |
| [MinGit release](https://github.com/git-for-windows/git/releases/tag/v2.53.0.windows.3) | MinGit 2.53.0.3 64-bit ZIP、GitHub release APIのSHA256 |

AMD公式のOS/PyTorch対応があっても、Forge Neo・各モデル・拡張の組み合わせまでAMDが認証しているとは解釈しません。モデル生成の成功判定には利用者のAMD実機での検証が必要です。
