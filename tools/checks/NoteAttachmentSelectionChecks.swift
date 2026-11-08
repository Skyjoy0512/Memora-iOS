import Foundation

@main
enum NoteAttachmentSelectionChecks {
  static func main() {
    let a = UUID(), b = UUID(), c = UUID()
    var selection = NoteAttachmentSelection()
    precondition(selection.isEmpty)
    selection.toggle(a)
    selection.toggle(b)
    selection.toggle(c)
    precondition(selection.ids == [a, b, c], "selection keeps tap order")

    // Deselecting and reselecting appends, matching the saved order.
    selection.toggle(b)
    precondition(selection.ids == [a, c])
    selection.toggle(b)
    precondition(selection.ids == [a, c, b])

    // Duplicate toggles never duplicate an id, and membership stays in sync.
    selection.toggle(a)
    selection.toggle(a)
    precondition(selection.ids == [c, b, a] && selection.contains(a) && selection.contains(b))
    selection.toggle(c)
    selection.toggle(b)
    selection.toggle(a)
    precondition(selection.isEmpty && !selection.contains(a))

    print("NoteAttachmentSelectionChecks: passed (tap order, deselect/reselect append, no duplicates, empty state)")
  }
}
