# ContextualRotation

[![Swift](https://img.shields.io/badge/Swift-5.7+-orange.svg)](https://swift.org)[![iOS](https://img.shields.io/badge/iOS-16.0+-blue.svg)](https://developer.apple.com/ios/)[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A native Swift package that brings Android's brilliant contextual rotation button to iOS.

When the iOS system orientation lock is enabled and the user rotates their physical device, `ContextualRotation` smartly detects the hardware movement and slides a floating button into the corner of the screen. Tapping it safely bypasses the system lock, forcing your app to rotate seamlessly.

It feels completely native, respects the user's system preferences, and provides a perfect one-tap escape hatch for immersive apps.

## Features

- **Raw Hardware Physics:** Uses `CMMotionManager` to read device gravity vectors, flawlessly detecting physical device orientation completely independent of iOS's internal `UIInterfaceOrientation` system locks.
- **Dynamic Corner Anchoring:** Automatically calculates the physical bottom of the device based on hand placement. The button dynamically swaps layout constraints to ensure it always appears exactly under the user's thumb, regardless of the locked UI state.
- **Icon Counter-Rotation:** Uses geometric transforms to perfectly counter-rotate the button's icon against the locked UI, ensuring the arrows always face physical "Up".
- **Pure Modern Swift:** Built from the ground up for modern iOS. Utilizes Swift Concurrency (`Task`), strict `@MainActor` isolation, and the new iOS 16 `UIWindowScene.requestGeometryUpdate` API. Zero legacy `@objc` runtime attributes.

## Requirements

- iOS 16.0+
- Xcode 14.0+
- Swift 5.7+

## Installation

You can install `ContextualRotation` using Swift Package Manager (SPM).

In Xcode:

1. Go to **File > Add Package Dependencies...**
2. Enter the repository URL for this package.
3. Select the version or branch you wish to integrate and add it to your project.

## Implementation Guide

To allow `ContextualRotation` to forcefully rotate the screen while the system lock is on, it must become the source of truth for your app's allowed orientations.

### SwiftUI

In a SwiftUI app, use `@UIApplicationDelegateAdaptor` to bridge the orientation requests to the library, and start the manager on your main window scene.

```swift
import SwiftUI
import ContextualRotation

// 1. Create an AppDelegate to intercept iOS orientation requests
@MainActor
class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
    // Defer entirely to the ContextualRotation library's state
    return ContextualRotation.shared.currentLockedOrientation
  }
}

@main
struct YourAwesomeApp: App {
  // 2. Inject the AppDelegate into your SwiftUI lifecycle
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    WindowGroup {
      ContentView()
        .onAppear {
          setupRotationBypass()
        }
    }
  }

  @MainActor
  private func setupRotationBypass() {
    // 3. Safely extract the active window scene and start the manager
    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
    ContextualRotation.shared.start(in: windowScene)
  }
}
```

### UIKit

If you are using a standard UIKit architecture, simply update your `AppDelegate` and `SceneDelegate`.

In `AppDelegate.swift`:

```swift
import UIKit
import ContextualRotation

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
  func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
    return ContextualRotation.shared.currentLockedOrientation
  }
}
```

In `SceneDelegate.swift`:

```swift
import UIKit
import ContextualRotation

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    guard let windowScene = (scene as? UIWindowScene) else { return }

    let window = UIWindow(windowScene: windowScene)
    // Setup your root view controller here...
    self.window = window
    window.makeKeyAndVisible()

    // Attach the contextual rotation listener
    ContextualRotation.shared.start(in: windowScene)
  }
}
```

### API Reference

**`ContextualRotation`**  
The core orchestrator of the hardware tracking and UI injection pipeline. It is strictly enforced as a thread-safe singleton on the `@MainActor`.

- **`static let shared: ContextualRotation`**  
  Access the global, shared instance of the manager.

- **`func start(in windowScene: UIWindowScene)`**  
  Initializes the accelerometer motion tracking and attaches the invisible overlay window to the provided scene. The button will remain hidden until a physical rotation mismatch is detected.

- **`var currentLockedOrientation: UIInterfaceOrientationMask`**  
  The dynamic state variable that your host application's `AppDelegate` must return. This acts as the bridge allowing iOS to execute the forced geometry update when the user taps the floating button.

### Permissions Required

Unlike features that access the camera or the user's photo library, reading raw accelerometer data via `CMMotionManager` requires zero privacy strings in your `Info.plist`.

There are no permission prompts or system popups required. The library operates silently, securely, and immediately out of the box.

## License

This project is licensed under the MIT License.
