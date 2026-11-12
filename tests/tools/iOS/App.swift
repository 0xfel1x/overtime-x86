import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let lines = ToolCheck.run() + ["asset color: \(UIColor(named: "AccentColor") == nil ? "missing" : "found")"]
        let text = lines.joined(separator: "\n")
        // Also written to Documents/check.txt so that a script can read the results.
        if let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? text.write(to: folder.appendingPathComponent("check.txt"), atomically: true, encoding: .utf8)
        }
        let label = UILabel()
        label.numberOfLines = 0
        label.text = text
        label.backgroundColor = .systemBackground
        let controller = UIViewController()
        controller.view = label
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = controller
        window?.makeKeyAndVisible()
        return true
    }
}
