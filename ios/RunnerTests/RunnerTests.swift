import Flutter
import UIKit
import UserNotifications
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
  }

  @MainActor
  func testBadgeIsClearedWhenSceneBecomesActive() async throws {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first { $0.delegate is SceneDelegate })
    let delegate = try XCTUnwrap(scene.delegate as? SceneDelegate)
    if #available(iOS 16.0, *) {
      try await UNUserNotificationCenter.current().setBadgeCount(5)
    } else {
      UIApplication.shared.applicationIconBadgeNumber = 5
    }
    XCTAssertEqual(UIApplication.shared.applicationIconBadgeNumber, 5)

    delegate.sceneDidBecomeActive(scene)

    let cleared = expectation(for: NSPredicate { _, _ in
      UIApplication.shared.applicationIconBadgeNumber == 0
    }, evaluatedWith: nil)
    await fulfillment(of: [cleared], timeout: 5)
  }

}
