import ExpoModulesCore
import UIKit

public class MRZScannerModule: Module {
    public func definition() -> ModuleDefinition {
        Name("MRZScanner")

        AsyncFunction("scanMRZ") { (promise: Promise) in
            DispatchQueue.main.async {
                self.presentScanner(promise: promise)
            }
        }
    }

    private func presentScanner(promise: Promise) {
        guard let presenter = topViewController() else {
            promise.reject("ERR_UI", "Tarayıcı açılamadı: aktif bir ekran bulunamadı.")
            return
        }

        var completed = false

        let scanner = VisionViewController()
        scanner.modalPresentationStyle = .fullScreen

        scanner.completionHandler = { mrz in
            guard !completed else { return }
            completed = true
            scanner.dismiss(animated: true) {
                promise.resolve(mrz)
            }
        }

        scanner.onCancel = {
            guard !completed else { return }
            completed = true
            promise.reject("ERR_CANCELLED", "MRZ tarama iptal edildi.")
        }

        presenter.present(scanner, animated: true)
    }

    private func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let baseController: UIViewController?

        if let base {
            baseController = base
        } else {
            let scenes = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .filter { $0.activationState == .foregroundActive }
            let window = scenes
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
            baseController = window?.rootViewController
        }

        if let nav = baseController as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }

        if let tab = baseController as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }

        if let presented = baseController?.presentedViewController {
            return topViewController(base: presented)
        }

        return baseController
    }
}
