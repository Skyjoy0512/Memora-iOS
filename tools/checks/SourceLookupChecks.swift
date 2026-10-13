import Foundation

@main
struct SourceLookupChecks {
  static func main() {
    for count in [0, 1, 100, 1_000] {
      var values = (0..<count).map { Value(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0 + 1))!, text: "資料\($0)", allowed: true) }
      var index = IdentifiableIndex<Value>()
      for value in values { precondition(index.element(value.id, in: values) == values.first { $0.id == value.id }) }
      if count >= 100 {
        measure("id-lookup-linear", count: count) { values.reduce(0) { total, value in total + (values.first { $0.id == value.id } == nil ? 0 : 1) } }
        measure("id-lookup-indexed", count: count) { values.reduce(0) { total, value in total + (index.element(value.id, in: values) == nil ? 0 : 1) } }
      }
      if count > 0 {
        let id = values[0].id
        values[0].text = "編集"
        values[0].allowed = false
        index.invalidate()
        precondition(index.element(id, in: values)?.text == "編集" && index.element(id, in: values)?.allowed == false)
        values.append(Value(id: id, text: "重複", allowed: true))
        index.invalidate()
        precondition(index.element(id, in: values)?.allowed == false)
        values.removeAll { $0.id == id }
        index.invalidate()
        precondition(index.element(id, in: values) == nil)
        values.reverse()
        index.invalidate()
        for value in values { precondition(index.element(value.id, in: values) == value) }
      }
    }
    print("SourceLookupChecks: passed (0/1/100/1000, current edited permissions, deletion, ordering, first duplicate)")
  }

  static func measure(_ name: String, count: Int, work: () -> Int) {
    var samples: [Double] = []
    for _ in 0..<21 {
      let start = ContinuousClock.now
      precondition(work() == count)
      let d = start.duration(to: .now).components
      samples.append(Double(d.seconds) * 1_000 + Double(d.attoseconds) / 1e15)
    }
    samples.sort()
    print(String(format: "%@,%d,median=%.3f,p95=%.3f,max=%.3f", name, count, samples[10], samples[19], samples[20]))
  }
}
struct Value: Identifiable, Equatable { var id: UUID; var text: String; var allowed: Bool }
