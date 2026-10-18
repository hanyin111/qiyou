import SwiftUI

// Test-only host: renders the production widget view without starting Flutter,
// requesting notification permissions or accessing saved community accounts.
@main
struct PreviewHostApp: App {
  var body: some Scene { WindowGroup { Color(UIColor.systemBackground) } }
}
