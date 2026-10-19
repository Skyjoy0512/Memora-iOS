import SwiftUI

enum SettingsIconStyle {
  case tile
  case monochrome
}

extension EnvironmentValues {
  @Entry var settingsIconStyle: SettingsIconStyle = .monochrome
}
