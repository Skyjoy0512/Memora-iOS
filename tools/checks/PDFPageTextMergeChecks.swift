import Foundation

enum PDFPageTextMergeChecks {
  static func run() {
    let original = " \nHeading\nThe  result\tis available.\nTotal −10.50\n "
    let merged = PDFPageTextMerge.merge(digitalText: original, recognizedLines: [
      "The result is available.", "Heading", "Total −10.50", "The result is not available.",
      "Total -10.50", "Total −10.500", "total −10.50", "Total −10.50.", "\t ",
      "New   figure label", "New figure label"
    ])
    precondition(merged == "Heading\nThe  result\tis available.\nTotal −10.50\n" +
      "The result is not available.\nTotal -10.50\nTotal −10.500\ntotal −10.50\nTotal −10.50.\nNew   figure label")
    precondition(PDFPageTextMerge.merge(digitalText: "100 +10 0.10 ABC", recognizedLines: ["10", "-10", "0.1", "abc"]) ==
      "100 +10 0.10 ABC\n10\n-10\n0.1\nabc")
    precondition(PDFPageTextMerge.merge(digitalText: "wording", recognizedLines: ["word"]) == "wording\nword")
    precondition(PDFPageTextMerge.merge(digitalText: "Alpha\nBeta", recognizedLines: [" Alpha   Beta "]) == "Alpha\nBeta")
    precondition(PDFPageTextMerge.merge(digitalText: "", recognizedLines: ["One  two", "One two", "two", "Two"]) ==
      "One  two\nTwo")
    precondition(PDFPageTextMerge.merge(digitalText: "Caf\u{e9}", recognizedLines: ["Cafe\u{301}"]) == "Caf\u{e9}\nCafe\u{301}")
    precondition(PDFPageTextMerge.merge(digitalText: " ", recognizedLines: [" ", "\n"]).isEmpty)
    precondition(PDFPageTextMerge.merge(digitalText: "A, B", recognizedLines: ["A B", "A, B", "A,  B"]) == "A, B\nA B")
    let repetitive = String(repeating: "token ", count: 20_000).trimmingCharacters(in: .whitespaces)
    let newLine = String(repeating: "token ", count: 700) + "boundary"
    let large = PDFPageTextMerge.merge(digitalText: repetitive, recognizedLines: [newLine, newLine])
    precondition(large == repetitive + "\n" + newLine)
    print("PDFPageTextMergeChecks: PASS. Digital text preserved; whitespace-only duplicates suppressed; differing digits, signs, case, punctuation, Unicode spelling and negation retained; repetitive OCR prefixes remain bounded. Host text checks only.")
  }
}
