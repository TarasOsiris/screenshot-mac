import SwiftUI

#if os(macOS)
enum HelpBlock {
    case heading(LocalizedStringKey)
    case paragraph(LocalizedStringKey)
    case bullet(LocalizedStringKey)
    case tip(LocalizedStringKey)
}
#endif
