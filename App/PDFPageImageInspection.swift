import CoreGraphics
import Foundation

/// Inspect resource metadata rather than decompressing image/content streams.
/// Unused image resources can cause extra OCR; inline images and vector outlines
/// are not identified by this metadata-only inspection.
enum PDFPageImageInspection {
  static func containsImage(in page: CGPDFPage) -> Bool {
    let inspection = Inspection()
    guard var dictionary = page.dictionary else { return true }
    // Resources are inheritable through the page tree. A malformed or cyclic
    // parent chain is uncertain, so it receives the same conservative OCR pass.
    for _ in 0..<32 {
      var resourceObject: CGPDFObjectRef?
      if CGPDFDictionaryGetObject(dictionary, "Resources", &resourceObject) {
        var resources: CGPDFDictionaryRef?
        guard let resourceObject, CGPDFObjectGetValue(resourceObject, .dictionary, &resources), let resources else { return true }
        return inspection.resourcesContainImage(resources, depth: 0)
      }
      var parentObject: CGPDFObjectRef?
      guard CGPDFDictionaryGetObject(dictionary, "Parent", &parentObject) else { return false }
      var parent: CGPDFDictionaryRef?
      guard let parentObject, CGPDFObjectGetValue(parentObject, .dictionary, &parent), let parent else { return true }
      dictionary = parent
    }
    return true
  }

  private final class Inspection {
    private var remaining = 256

    func resourcesContainImage(_ resources: CGPDFDictionaryRef, depth: Int) -> Bool {
      guard depth <= 8, remaining > 0 else { return true }
      remaining -= 1
      var object: CGPDFObjectRef?
      guard CGPDFDictionaryGetObject(resources, "XObject", &object) else { return false }
      var objects: CGPDFDictionaryRef?
      guard let object, CGPDFObjectGetValue(object, .dictionary, &objects), let objects else { return true }
      guard CGPDFDictionaryGetCount(objects) <= remaining else { return true }
      var candidate = false
      // ApplyBlock permits an early stop; the older ApplyFunction callback would
      // still enumerate every entry of an adversarially large resource table.
      CGPDFDictionaryApplyBlock(objects, { _, value, _ in
        guard self.remaining > 0 else { candidate = true; return false }
        self.remaining -= 1
        candidate = self.objectContainsImage(value, depth: depth + 1)
        return !candidate
      }, nil)
      return candidate
    }

    private func objectContainsImage(_ object: CGPDFObjectRef, depth: Int) -> Bool {
      guard depth <= 8, !Task.isCancelled else { return true }
      var stream: CGPDFStreamRef?
      guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
            let dictionary = CGPDFStreamGetDictionary(stream) else { return true }
      var subtype: UnsafePointer<CChar>?
      guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype else { return true }
      if strcmp(subtype, "Image") == 0 { return true }
      guard strcmp(subtype, "Form") == 0 else { return true }
      var resources: CGPDFDictionaryRef?
      guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources else { return true }
      // Depth and shared node budgets also bound cyclic Form/resource graphs.
      return resourcesContainImage(resources, depth: depth + 1)
    }
  }
}
