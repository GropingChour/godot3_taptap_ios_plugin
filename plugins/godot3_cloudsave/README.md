# Godot3 CloudSave Plugin (iCloud)

This plugin implements a Cloud Save system for Godot 3.x using Apple's CloudKit, mirroring the interface of the TapTap SDK.

## ⚠️ Critical iOS Setup Requirement

The error message `In order to use CloudKit, your process must have a ... entitlement` indicates that the **iCloud capability is not enabled** in your Xcode project.

You **must** manually configure this in Xcode after exporting your project, or use a post-export script if you have one. The `.gdip` file cannot automatically add these signed entitlements.

### Setup Steps in Xcode:

1.  Export your Godot project to iOS.
2.  Open the generated `.xcodeproj` in Xcode.
3.  Select your project root in the Project Navigator.
4.  Select your App Target.
5.  Go to the **Signing & Capabilities** tab.
6.  Click **+ Capability** (top left of the tab).
7.  Search for and select **iCloud**.
8.  In the iCloud section that appears:
    *   Check **CloudKit**.
    *   Under **Containers**, click `+` to add a new container (usually `iCloud.your.bundle.id`).
    *   Make sure the container is checked.

### Troubleshooting

**Error: "Failed to install embedded profile... (Attempted to install a Beta profile without the proper entitlement.)"**

This error (0xe800801f) occurs because you are trying to install a build signed with an **App Store** or **Ad Hoc** distribution profile directly from Xcode to a device. This is not allowed.

**Solution:**
1.  **Switch to Development Profile**:
    *   Go to **Signing & Capabilities** tab in Xcode.
    *   Uncheck "Automatically manage signing" (temporarily) if needed.
    *   In "Provisioning Profile", select a profile that has **"Development"** in its name (e.g., `Backpack Battles Dev`).
    *   If you don't have one, go to Apple Developer Portal, create a new profile of type **"iOS App Development"**, download it, and select it here.
    *   **Crucial**: Ensure the device you are testing on is registered in the Devices list of that Development Profile.
2.  **Verify Code Signing Identity**:
    *   Go to **Build Settings** > **Signing**.
    *   Ensure **Code Signing Identity** > **Debug** is set to **"Apple Development"** (or "iOS Developer").
3.  **Clean & Rebuild**:
    *   Menu: `Product` > `Clean Build Folder`.
    *   Re-run the app.

**Note**: If you want to test the *exact* build that will go to the store (using Distribution profile), you cannot use the "Play" button in Xcode. You must use `Product` > `Archive`, then export as "Ad Hoc" or "TestFlight" and install via those methods.

### Creating a New iCloud Container

If you need to create a new container (e.g., `iCloud.com.example.game`):

1.  **Via Xcode (Easiest)**:
    *   Go to **Signing & Capabilities** > **iCloud**.
    *   Click the **+** button under the **Containers** list.
    *   Enter your new container ID (it usually starts with `iCloud.`).
    *   Click **OK**. Xcode will automatically register this container in your Apple Developer account and update your App ID entitlements.

2.  **Via Apple Developer Portal**:
    *   Go to [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list/cloudContainer).
    *   Select **Identifiers** from the sidebar.
    *   Click the **+** button.
    *   Select **iCloud Containers** and click **Continue**.
    *   Enter a **Description** and **Identifier** (e.g., `iCloud.com.example.game`).
    *   Click **Continue** and **Register**.
    *   *Then, you must go back to your App ID configuration and check this new container to associate them.*

### Why is this necessary?
CloudKit requires a provisioning profile that includes the `com.apple.developer.icloud-services` entitlement. This is strictly enforced by Apple and must be configured in your Apple Developer account and Xcode project.

## API Usage

Use the `ICloudSave` singleton in GDScript (auto-loaded):

```gdscript
# Connect signals
ICloudSave.connect("onCreateArchiveSuccess", self, "_on_save_success")
ICloudSave.connect("onCreateArchiveFailed", self, "_on_save_fail")

# Create a save
var meta = {"level": 5, "gold": 100}
ICloudSave.createArchive(meta, "user://save.dat", "user://cover.png")

# List saves
ICloudSave.getArchiveList()
```
