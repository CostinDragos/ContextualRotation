import CoreMotion
import UIKit

@MainActor
public class ContextualRotation {
  public static let shared = ContextualRotation()

  private let motionManager = CMMotionManager()
  private var overlayWindow: UIWindow?
  private var rotationButton: UIButton!
  
  private var trailingConstraint: NSLayoutConstraint!
  private var leadingConstraint: NSLayoutConstraint!

  private var physicalOrientation: UIInterfaceOrientation = .unknown

  public var currentLockedOrientation: UIInterfaceOrientationMask = .all
  private var targetInterfaceOrientation: UIInterfaceOrientation = .unknown

  private var hideButtonTask: Task<Void, Never>?

  private init() {}

  public func start(in windowScene: UIWindowScene) {
    setupOverlayWindow(in: windowScene)
    startMotionTracking()
    
    NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
      self?.evaluateUI()
    }
    
    NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
      self?.currentLockedOrientation = .all
    }
  }

  private func setupOverlayWindow(in windowScene: UIWindowScene) {
    let window = UIWindow(windowScene: windowScene)
    window.windowLevel = .alert + 1
    window.backgroundColor = .clear
    window.isUserInteractionEnabled = false

    let rootVC = UIViewController()
    rootVC.view.backgroundColor = .clear
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
    
    trailingConstraint = rotationButton.trailingAnchor.constraint(equalTo: rootVC.view.safeAreaLayoutGuide.trailingAnchor, constant: -20)
    leadingConstraint = rotationButton.leadingAnchor.constraint(equalTo: rootVC.view.safeAreaLayoutGuide.leadingAnchor, constant: 20)
    
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
      guard let self, let data else { return }
      processAcceleration(data.acceleration)
    }
  }

  private func processAcceleration(_ acceleration: CMAcceleration) {
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
      evaluateUI()
    }
  }

  private func evaluateUI() {
    guard let windowScene = overlayWindow?.windowScene else { return }
    let uiOrientation = windowScene.interfaceOrientation

    if physicalOrientation == uiOrientation {
      toggleButton(show: false)
      return
    }

    if physicalOrientation == .portraitUpsideDown { return }

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
      UIView.animate(withDuration: 0.3) {
        self.rotationButton.alpha = 1.0
        self.rotationButton.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
      } completion: { _ in
        UIView.animate(withDuration: 0.1) {
          self.rotationButton.transform = .identity
        }
      }

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
