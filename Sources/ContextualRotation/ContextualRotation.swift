import CoreMotion
import UIKit

/// A native manager that tracks physical hardware rotation and provides an Android-Style
/// Contextual bypass button for when the iOS system orientation lock is enabled.
@MainActor
public class ContextualRotation {
  /// Shared Singleton instance for the contextual rotation manager.
  public static let shared = ContextualRotation()

  private let motionManager = CMMotionManager()
  private var overlayWindow: UIWindow?
  private var rotationButton: UIButton!

  private var trailingConstraint: NSLayoutConstraint!
  private var leadingConstraint: NSLayoutConstraint!

  private var physicalOrientation: UIInterfaceOrientation = .unknown

  /// The dynamic orientation mask that the host application's `App Delegate` must return.
  /// By returning this value in `supportedInterfaceOrientationsFor`, you allow the
  /// library to forefully bypass the system lock when the user taps the button.
  public var currentLockedOrientation: UIInterfaceOrientationMask = .all

  private var targetInterfaceOrientation: UIInterfaceOrientation = .unknown

  private var isUIAnimatingRotation = false
  private var evaluationTask: Task<Void, Never>?
  private var hideButtonTask: Task<Void, Never>?

  private init() {}

  /// Initializes the hardware motion tracking and attaches the contextual rotation listener to the
  /// provided window scene
  ///
  /// - Parameter windowScene: The `UIWindowScene` where the invisible overlay and floating point
  /// should be injected.
  public func start(in windowScene: UIWindowScene) {
    setupOverlayWindow(in: windowScene)
    startMotionTracking()

    NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main,
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.evaluateUI()
      }
    }

    NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification,
      object: nil,
      queue: .main,
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.currentLockedOrientation = .all
        self?.physicalOrientation = .unknown
        self?.toggleButton(show: false)
      }
    }
  }

  private func setupOverlayWindow(in windowScene: UIWindowScene) {
    let window = PassThroughWindow(windowScene: windowScene)
    window.windowLevel = .alert + 1
    window.backgroundColor = .clear
    window.isUserInteractionEnabled = false

    let rootVC = OverlayViewController()
    rootVC.view.backgroundColor = .clear
    window.rootViewController = rootVC

    rootVC.onTransitionStart = { [weak self] in
      self?.evaluationTask?.cancel()
      self?.isUIAnimatingRotation = true
      self?.toggleButton(show: false)
    }

    rootVC.onTransitionEnd = { [weak self] in
      self?.isUIAnimatingRotation = false
      self?.evaluateUI()
    }

    window.rootViewController = rootVC

    rotationButton = UIButton(type: .system)
    let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
    let image = UIImage(systemName: "arrow.triangle.2.circlepath", withConfiguration: config)
    rotationButton.setImage(image, for: .normal)
    rotationButton.backgroundColor = .black.withAlphaComponent(0.7)
    rotationButton.tintColor = .white
    rotationButton.layer.cornerRadius = 25
    rotationButton.alpha = 0

    rotationButton.isUserInteractionEnabled = true
    // rotationButton.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
    let tapAction = UIAction { [weak self] _ in
      self?.buttonTapped()
    }
    rotationButton.addAction(tapAction, for: .touchUpInside)

    rootVC.view.addSubview(rotationButton)

    rotationButton.translatesAutoresizingMaskIntoConstraints = false

    trailingConstraint = rotationButton.trailingAnchor.constraint(
      equalTo: rootVC.view.safeAreaLayoutGuide.trailingAnchor,
      constant: -20,
    )
    leadingConstraint = rotationButton.leadingAnchor.constraint(
      equalTo: rootVC.view.safeAreaLayoutGuide.leadingAnchor,
      constant: 20,
    )

    NSLayoutConstraint.activate([
      rotationButton.widthAnchor.constraint(equalToConstant: 50),
      rotationButton.heightAnchor.constraint(equalToConstant: 50),
      rotationButton.bottomAnchor.constraint(
        equalTo: rootVC.view.safeAreaLayoutGuide.bottomAnchor,
        constant: -20,
      ),
      trailingConstraint,
    ])

    overlayWindow = window
    window.isHidden = false
  }

  private func startMotionTracking() {
    guard motionManager.isAccelerometerAvailable else { return }

    motionManager.accelerometerUpdateInterval = 0.2
    motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
      MainActor.assumeIsolated {
        guard let self, let data else { return }
        self.processAcceleration(data.acceleration)
      }
    }
  }

  private func processAcceleration(_ acceleration: CMAcceleration) {
    let x = acceleration.x
    let y = acceleration.y
    let z = acceleration.z

    guard x != 0 || y != 0 || z != 0 else { return }
    guard abs(z) < 0.85 else { return }

    let isLandscape = abs(x) > abs(y) + 0.15
    let isPortrait = abs(y) > abs(x) + 0.15
    guard isLandscape || isPortrait else { return }

    let threshold = 0.75
    var newPhysicalOrientation: UIInterfaceOrientation = physicalOrientation

    if acceleration.x >= threshold {
      newPhysicalOrientation = .landscapeLeft
    } else if acceleration.x <= -threshold {
      newPhysicalOrientation = .landscapeRight
    } else if acceleration.y >= threshold {
      newPhysicalOrientation = .portraitUpsideDown
    } else if acceleration.y <= -threshold {
      newPhysicalOrientation = .portrait
    }

    if newPhysicalOrientation != physicalOrientation, newPhysicalOrientation != .unknown {
      physicalOrientation = newPhysicalOrientation
      evaluationTask?.cancel()
      evaluationTask = Task { [weak self] in
        do {
          try await Task.sleep(nanoseconds: 300_000_000)
          self?.evaluateUI()
        } catch {
          // Native rotation started.
        }
      }
    }
  }

  private func evaluateUI() {
    guard !isUIAnimatingRotation else { return }
    guard let windowScene = overlayWindow?.windowScene else { return }
    let uiOrientation = windowScene.interfaceOrientation
    guard uiOrientation != .unknown else { return }

    guard physicalOrientation != .unknown else {
      toggleButton(show: false)
      return
    }

    if physicalOrientation == .portraitUpsideDown { return }

    if physicalOrientation == uiOrientation {
      toggleButton(show: false)
      return
    }

    targetInterfaceOrientation = physicalOrientation

    if targetInterfaceOrientation == .landscapeRight {
      trailingConstraint.isActive = false
      leadingConstraint.isActive = true
    } else if targetInterfaceOrientation == .landscapeLeft {
      leadingConstraint.isActive = false
      trailingConstraint.isActive = true
    } else {
      if uiOrientation == .landscapeLeft {
        trailingConstraint.isActive = false
        leadingConstraint.isActive = true
      } else {
        leadingConstraint.isActive = false
        trailingConstraint.isActive = true
      }
    }

    overlayWindow?.rootViewController?.view.layoutIfNeeded()

    toggleButton(show: true)
  }

  private func toggleButton(show: Bool) {
    guard let window = overlayWindow else { return }

    if show {
      window.isUserInteractionEnabled = true
      UIView.animate(
        withDuration: 0.3,
        delay: 0,
        options: [.allowUserInteraction, .curveEaseOut],
        animations: {
          self.rotationButton.alpha = 1.0
          self.rotationButton.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
        }, completion: { _ in
          UIView.animate(
            withDuration: 0.1,
            delay: 0,
            options: [.allowUserInteraction, .curveEaseIn],
            animations: {
              self.rotationButton.transform = .identity
            },
          )
        },
      )

      hideButtonTask?.cancel()
      hideButtonTask = Task {
        do {
          try await Task.sleep(nanoseconds: 5_000_000_000)
          self.hideButton()
        } catch {
          // Task was cancelled, do nothing
        }
      }
    } else {
      hideButton()
    }
  }

  private func hideButton() {
    hideButtonTask?.cancel()

    overlayWindow?.isUserInteractionEnabled = false
    UIView.animate(withDuration: 0.3) {
      self.rotationButton.alpha = 0.0
    }
  }

  private func buttonTapped() {
    hideButton()

    switch targetInterfaceOrientation {
    case .portrait:
      currentLockedOrientation = .portrait
    case .landscapeLeft:
      currentLockedOrientation = .landscapeLeft
    case .landscapeRight:
      currentLockedOrientation = .landscapeRight
    default:
      break
    }

    guard let windowScene = overlayWindow?.windowScene else { return }

    let geometryUpdate = UIWindowScene.GeometryPreferences
      .iOS(interfaceOrientations: currentLockedOrientation)

    windowScene.requestGeometryUpdate(geometryUpdate) { error in
      print("ContextualRotation: Failed to rotate -> \(error.localizedDescription)")
    }
  }
}

// MARK: - Native Rotation Detection

/// A lightweight view controller that intercepts native system rotation events.
private class OverlayViewController: UIViewController {
  var onTransitionStart: (@MainActor () -> Void)?
  var onTransitionEnd: (@MainActor () -> Void)?

  override func viewWillTransition(
    to size: CGSize,
    with coordinator: any UIViewControllerTransitionCoordinator,
  ) {
    super.viewWillTransition(to: size, with: coordinator)

    onTransitionStart?()

    coordinator.animate(alongsideTransition: nil) { _ in
      self.onTransitionEnd?()
    }
  }
}

// MARK: - Pass-Through Window

/// A window that ignores touches on its empty background space, allowing them to pass through to
/// the application below, while still catching touches on its subviews.
private class PassThroughWindow: UIWindow {
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let hitView = super.hitTest(point, with: event)

    if hitView == self || hitView == rootViewController?.view {
      return nil
    }
    return hitView
  }
}
