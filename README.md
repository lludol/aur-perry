# AUR package for Perry CLI

Arch User Repository (AUR) package for [Perry](https://github.com/PerryTS/perry) — compile TypeScript to native executables.

## Package

| Package   | Description  |
|-----------|--------------|
| **perry** | Source build |

## Install

Using an AUR helper (e.g. [yay](https://github.com/Jguer/yay)):

```bash
yay -S perry
```

Manual build from this repo:

```bash
cd perry
makepkg -si
```

## Usage

After install, the `perry` binary is in your `PATH`:

```bash
perry --help
# or
/usr/bin/perry --help
```

The PKGBUILD is automatically updated via GitHub Actions (see [MAINTAINER.md](MAINTAINER.md) for details).

## License

The PKGBUILDs and this repo are licensed under [0BSD](LICENSE). Perry itself is [MIT](https://github.com/PerryTS/perry/blob/main/LICENSE)-licensed.
