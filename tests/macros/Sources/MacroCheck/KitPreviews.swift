#if canImport(UIKit)
import UIKit

#Preview { UILabel() }
#Preview { UIViewController() }
#elseif canImport(AppKit)
import AppKit

#Preview { NSTextField(labelWithString: "AppKit") }
#Preview { NSViewController() }
#endif
