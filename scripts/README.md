# Local verification scripts

Run these from a clean checkout after installing the required toolchains:

- **Windows / Visual Studio Developer PowerShell:** `powershell -ExecutionPolicy Bypass -File .\scripts\verify.ps1`
- **Linux / macOS:** `bash ./scripts/verify.sh`

The scripts run Rust formatting, workspace checks and tests, then restore/build the Avalonia desktop project and run any `*Tests.csproj` projects. They stop on the first failing command. A successful build does **not** replace runtime audio testing on the target machine.

## Toolchain notes

- Install stable Rust with the `rustfmt` component and ensure `cargo` is on PATH.
- Install the .NET SDK matching the desktop project's `TargetFramework` in its `.csproj`.
- On Windows, use a Visual Studio Developer PowerShell if native build tools are required by the installed toolchain.
- On Linux, install the native CPAL/ALSA build prerequisites required by the distribution (CI currently installs `pkg-config` and `libasound2-dev`).

If formatting fails, run `cargo fmt --all`, inspect the resulting diff, and rerun the verification script. Do not skip the formatting check to make CI green.
