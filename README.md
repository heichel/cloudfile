# cloudfile

Cloud File CLI is a command-line utility for interacting with cloud-stored files on macOS. It allows users to materialize (download) or evict (remove locally while keeping in the cloud) files using Apple's `NSFileManager`.

Forked from [kevincar/cloudfile](https://github.com/kevincar/cloudfile). Added a synchronous option that is useful for use cases where the next command depends on the file being available locally (e.g. a [backup script](https://github.com/heichel/icloud-backup)).

## Usage

```sh
cloudfile <command> <file-path>
```

### Commands
- `materialize` - Downloads the file from the cloud
- `materialize-sync` - Downloads the file from the cloud synchronously (blocks until the file is fully downloaded)
- `evict` - Removes the local copy while retaining it in the cloud

## Building and Installing

Ensure you have CMake installed before proceeding.

### Steps:
1. Clone the repository:
   ```sh
   git clone <repo-url>
   cd <repo-name>
   ```
2. Run the build script:
   ```sh
   chmod +x scripts/build.sh
   ./scripts/build.sh
   ```
3. Run the cloudfile binary:
   ```sh
   ./build/cloudfile
   ```


## Requirements
- macOS
- CMake
- Clang (default on macOS)
