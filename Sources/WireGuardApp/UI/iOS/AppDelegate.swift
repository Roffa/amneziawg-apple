// SPDX-License-Identifier: MIT
// Copyright © 2018-2023 WireGuard LLC. All Rights Reserved.

import UIKit
import os.log

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    var mainVC: MainViewController?
    var isLaunchedForSpecificAction = false

    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Logger.configureGlobal(tagged: "APP", withFilePath: FileManager.logFileURL?.path)

        if let launchOptions = launchOptions {
            if launchOptions[.url] != nil || launchOptions[.shortcutItem] != nil {
                isLaunchedForSpecificAction = true
            }
        }

        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    @discardableResult
    func ensureMainViewController() -> MainViewController {
        if let mainVC = self.mainVC {
            return mainVC
        }
        let mainVC = MainViewController()
        self.mainVC = mainVC
        return mainVC
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        mainVC?.importFromDisposableFile(url: url)
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        mainVC?.refreshTunnelConnectionStatuses()
    }

    func applicationWillResignActive(_ application: UIApplication) {
        guard let allTunnelNames = mainVC?.allTunnelNames() else { return }
        application.shortcutItems = QuickActionItem.createItems(allTunnelNames: allTunnelNames)
    }

    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        handleShortcutItem(shortcutItem, completionHandler: completionHandler)
    }

    func handleShortcutItem(_ shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        guard shortcutItem.type == QuickActionItem.type else {
            completionHandler(false)
            return
        }
        let tunnelName = shortcutItem.localizedTitle
        mainVC?.showTunnelDetailForTunnel(named: tunnelName, animated: false, shouldToggleStatus: true)
        completionHandler(true)
    }
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    private var appDelegate: AppDelegate? {
        UIApplication.shared.delegate as? AppDelegate
    }

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        guard let appDelegate = appDelegate else { return }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = appDelegate.ensureMainViewController()
        self.window = window
        appDelegate.window = window
        window.makeKeyAndVisible()

        if let url = connectionOptions.urlContexts.first?.url {
            appDelegate.mainVC?.importFromDisposableFile(url: url)
        }

        if let shortcutItem = connectionOptions.shortcutItem {
            appDelegate.handleShortcutItem(shortcutItem) { _ in }
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        appDelegate?.mainVC?.importFromDisposableFile(url: url)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        appDelegate?.mainVC?.refreshTunnelConnectionStatuses()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        guard let app = appDelegate,
              let allTunnelNames = app.mainVC?.allTunnelNames() else { return }
        UIApplication.shared.shortcutItems = QuickActionItem.createItems(allTunnelNames: allTunnelNames)
    }

    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        appDelegate?.handleShortcutItem(shortcutItem, completionHandler: completionHandler) ?? completionHandler(false)
    }
}

extension AppDelegate {
    func application(_ application: UIApplication, shouldSaveApplicationState coder: NSCoder) -> Bool {
        return true
    }

    func application(_ application: UIApplication, shouldRestoreApplicationState coder: NSCoder) -> Bool {
        return !self.isLaunchedForSpecificAction
    }

    func application(_ application: UIApplication, viewControllerWithRestorationIdentifierPath identifierComponents: [String], coder: NSCoder) -> UIViewController? {
        guard let vcIdentifier = identifierComponents.last else { return nil }
        if vcIdentifier.hasPrefix("TunnelDetailVC:") {
            let tunnelName = String(vcIdentifier.suffix(vcIdentifier.count - "TunnelDetailVC:".count))
            if let tunnelsManager = mainVC?.tunnelsManager {
                if let tunnel = tunnelsManager.tunnel(named: tunnelName) {
                    return TunnelDetailTableViewController(tunnelsManager: tunnelsManager, tunnel: tunnel)
                }
            } else {
                // Show it when tunnelsManager is available
                mainVC?.showTunnelDetailForTunnel(named: tunnelName, animated: false, shouldToggleStatus: false)
            }
        }
        return nil
    }
}
