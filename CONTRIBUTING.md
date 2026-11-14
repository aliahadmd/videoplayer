# Contributing to LiPlayer

Thank you for your interest in contributing to **LiPlayer**!

LiPlayer is free, open-source software created by [Ali Ahad](https://aliahad.com) under [LI Labs](https://github.com/LiLabsAI), licensed under the **GNU General Public License v3.0 (`GPL-3.0-or-later`)** — see [LICENSE](LICENSE).

## Ways to contribute

- **Report bugs:** Open an issue on [GitHub Issues](https://github.com/LiLabsAI/LiPlayer/issues) with reproduction steps, sample media details (codec/container), your macOS version, and app version.
- **Suggest features & enhancements:** Open a feature request describing the use case and expected playback/library behavior.
- **Fork & submit pull requests:** Fork the repository on GitHub, create a focused branch from `main`, keep changes well-tested, and open a pull request explaining the motivation and verification you ran.

## Development & verification checks

Before opening a pull request, run the build and test suite on Apple Silicon:

```sh
python3 scripts/bootstrap.py
swift test
```

If your changes affect playback, packaging, UI, persistence, or workspace behavior, also run the packaged app verification checks:

```sh
python3 scripts/make-fixtures.py
python3 scripts/package.py --configuration debug --qa
python3 scripts/verify.py
python3 scripts/verify-workspace.py
```

## Licensing, ownership & attribution

- **Copyright & attribution:** Original LiPlayer source code and brand assets carry the copyright notice `Copyright (C) 2026 Ali Ahad` and are licensed under **GNU GPL v3.0 (`GPL-3.0-or-later`)** ([LICENSE](LICENSE)). Preserve existing copyright notices, [NOTICE.md](NOTICE.md), and source headers in forks and redistributions.
- **Copyleft guarantee:** Under GPLv3, anyone may freely study, modify, fork, and distribute LiPlayer, and any distributed modified versions or derivative works must also be licensed under GPLv3 with complete corresponding source code provided. LiPlayer source code may not be incorporated into distributed closed-source or proprietary derivatives.
- **Inbound = Outbound:** By submitting a contribution (pull request, patch, or commit) to this repository, you confirm that you have the right to submit it and agree that your contribution is licensed to the project and all downstream recipients under the **GNU General Public License v3.0 (`GPL-3.0-or-later`)**. Contributors retain copyright and Git attribution for their authored commits.
- **GPLv3 compatibility:** Do not introduce third-party code or libraries whose license terms conflict with GPLv3. See [NOTICE.md](NOTICE.md) and [ThirdParty/README.md](ThirdParty/README.md) for bundled native dependency notices.
