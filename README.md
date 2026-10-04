<p align="center">
  <img src="https://github.com/try-containers/Containers/blob/main/.github/256.png?raw=true" height="128">
  <h1 align="center">Containers</h1>
</p>

A modern, native macOS application for managing Linux containers using Apple's container runtime.

Containers pulls, builds and runs OCI images, and manages the containers and volumes made from them, from a dashboard and the menu bar. It is built on Apple's [Containerization](https://github.com/apple/containerization) package: each container runs in its own lightweight virtual machine, started directly by the app, with no daemon or command-line tools to install.

> [!IMPORTANT]
> Containers is an early version under active development, so you may run into bugs and rough edges. If you do, please [report them](https://github.com/try-containers/Containers/issues/new/choose).
> Contributions are encouraged and welcome, whether it's a fix, a feature or an improvement to the documentation: see the [Contribution Guide](https://github.com/try-containers/Containers/blob/main/CONTRIBUTING.md) to get started.

## Get started

### Requirements

- A Mac with Apple silicon
- macOS 26 or later

### Install

Download Containers from the [Mac App Store](). On first launch it sets up the container system, downloading the Linux kernel and init image it needs, and then opens the dashboard.

## Documentation

Guides and reference live in the [Containers wiki](https://github.com/try-containers/Containers/wiki):

- Getting started with images, containers and volumes
- Building images from a Dockerfile
- Reports, logs and troubleshooting
- Settings and storage
- Building the app from source

## Community

- Report a bug or request a feature by [opening an issue](https://github.com/try-containers/Containers/issues/new/choose).
- Read the [Contribution Guide](https://github.com/try-containers/Containers/blob/main/CONTRIBUTING.md) before sending a pull request.

This is a community-led effort, so we welcome as many contributors who can help.

<a href="https://www.buymeacoffee.com/armartinez" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/default-blue.png" alt="Buy Me A Coffee" height="41" width="174"></a>

## Development

[![Build](https://github.com/try-containers/Containers/actions/workflows/containers-build.yml/badge.svg)](https://github.com/try-containers/Containers/actions/workflows/containers-build.yml)

- Open `Containers.xcodeproj` in Xcode 26 or later. Copy `Configuration/Local.xcconfig.example` to `Configuration/Local.xcconfig` and set your team ID to sign the app.
- [AGENTS.md](AGENTS.md) describes the architecture, conventions and commands, for contributors and coding agents alike.

## License

**Containers is free, and will always be free.**

### The app

Download it from the Mac App Store and use it however you like — personally, at
work, or across your company. The released app is licensed to you under Apple's
standard end user terms, and costs nothing.

### The source code

The code in this repository is licensed
under the [PolyForm Noncommercial License 1.0.0](LICENSE.md):

- ✅ Read it, build it, and modify it
- ✅ Fork it and contribute changes back
- ✅ Use it for personal projects, study, and research
- ✅ Use it at nonprofits, schools, and government institutions
- ❌ Use it, or any part of it, for commercial purposes
- ❌ Sell it, or sell anything built from it

The intent is simple: development tools should be free. You should never have to
pay for this, and neither should anyone else — so nobody gets to take this work,
in whole or in part, and sell it.

Donations are welcome and unaffected by the license. If you need a commercial
license, open an issue.

> Releases published before this change were licensed under the Mozilla Public
> License 2.0 and remain available under those terms.
