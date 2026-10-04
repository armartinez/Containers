<p align="center">
  <img src="https://github.com/try-containers/Containers/blob/main/.github/256.png?raw=true" height="128">
  <h1 align="center">Containers</h1>
</p>

A modern, native macOS application for managing Linux containers using Apple's container runtime. 

<p align="center">
  <a href="">
      <img src="https://github.com/try-containers/Containers/blob/main/.github/store_badge.svg">
  </a>
</p>

## Getting Started

### First Launch

1. Launch the Containers app from your Applications folder
2. The app will automatically initialize the container system on first launch
3. Once initialized, the dashboard will show the main interface with tabs for Containers and Images

### Managing Images

1. Click the **Images** tab to view and manage container images
2. To pull a new image:
   - Click the **Pull Image** button
   - Enter the image reference (e.g., `docker.io/library/nginx:latest`, `alpine:latest`, `ubuntu:latest`)
   - Click **Pull** to download the image
3. View image details by clicking on an image name
4. Delete unused images with the trash icon

### Creating and Running Containers

1. Click the **Containers** tab
2. Click **Create Container** to configure a new container:
   - Select an image from the dropdown (pull an image first if needed)
   - Configure resources (CPU cores, memory)
   - Add environment variables if needed
   - Set up port mappings to expose container services
   - Configure the command and arguments (optional - uses image defaults if not specified)
3. Click **Create** to create the container
4. Start the container using the play button
5. View container logs, details, and inspect configuration by clicking the container name

### Menu Bar

The Containers app also runs in your menu bar, showing the current system status. Click the menu bar icon to:
- Quickly start/stop the container system
- Open the dashboard
- Access settings

### System Requirements

- macOS 26.0 or later
- Apple Silicon Mac (M1/M2/M3/M4)

## Contributing

This is a community-led effort, so we welcome as many contributors who can help. Read the [Contribution Guide](https://github.com/try-containers/Containers/blob/main/CONTRIBUTING.md) for more information.

<a href="https://www.buymeacoffee.com/armartinez" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/default-blue.png" alt="Buy Me A Coffee" height="41" width="174"></a>

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
