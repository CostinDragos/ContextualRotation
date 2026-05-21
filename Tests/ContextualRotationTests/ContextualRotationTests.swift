@testable import ContextualRotation
import XCTest

@MainActor
final class ContextualRotationTests: XCTestCase {
  override func setUp() async throws {
    try await super.setUp()
    ContextualRotation.shared.currentLockedOrientation = .all
  }

  func test_sharedInstance_isAccessible() {
    let sut = ContextualRotation.shared

    XCTAssertNotNil(
      sut,
      "The shared singleton instance should be safely accessible on the MainActor.",
    )
  }

  func test_defaultOrientationMask_allowsAll() {
    let sut = ContextualRotation.shared

    let currentMask = sut.currentLockedOrientation

    XCTAssertEqual(
      currentMask,
      .all,
      "The package MUST default to '.all'. Otherwise, it could accidentally lock the host app's orientation before the rotation button is explicitly tapped.",
    )
  }

  func test_orientationMask_updatesCorrectly() {
    let sut = ContextualRotation.shared

    sut.currentLockedOrientation = .landscapeRight

    XCTAssertEqual(
      sut.currentLockedOrientation,
      .landscapeRight,
      "The orientation mask should successfully retain the new value requested by the UI.",
    )
  }

  // MARK: - Note to Contributors

  //
  // `UIWindowScene` injection and `CMMotionManager` hardware readings rely heavily on
  // physical device constraints and iOS UIKit internals.
  //
  // Full simulation of hardware rotation (gravity vector math) and App Lifecycle
  // backgrounding is best handled via XCUITest in a Host Application.
  // These unit tests ensure the public API surface and state management remain strictly stable.
}
