import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Carries a picked photo into the editor as a sheet item.
struct PhotoEditRequest: Identifiable {
  let id = UUID()
  var data: Data
}
