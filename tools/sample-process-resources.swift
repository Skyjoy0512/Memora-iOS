import Darwin
import Foundation

// Read-only macOS host counters. Simulator processes are not iPhone hardware;
// these values must never be presented as device energy or thermal readings.
guard CommandLine.arguments.count == 2,
      let pid = CommandLine.arguments[1] == "self" ? getpid() : Int32(CommandLine.arguments[1]),
      pid > 0 else {
  fputs("Usage: sample-process-resources <positive-pid|self>\n", stderr)
  exit(64)
}

var usage = rusage_info_v4()
let result = withUnsafeMutablePointer(to: &usage) { pointer in
  pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { buffer in
    proc_pid_rusage(pid, RUSAGE_INFO_V4, buffer)
  }
}
guard result == 0 else {
  perror("proc_pid_rusage")
  exit(1)
}
// rusage_info CPU counters use Mach absolute ticks, not nanoseconds. Keep the
// raw counters and timebase so a report can verify its unit conversion.
var timebase = mach_timebase_info_data_t()
guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom > 0 else { exit(1) }
let secondsPerTick = Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
let sample: [String: Any] = [
  "scope": "macOS host process counters; not iPhone battery or thermal data",
  "pid": pid,
  "timestamp": ISO8601DateFormatter().string(from: Date()),
  "hostUptimeSeconds": ProcessInfo.processInfo.systemUptime,
  "processStartAbsoluteTime": usage.ri_proc_start_abstime,
  "userCpuAbsoluteTicks": usage.ri_user_time,
  "systemCpuAbsoluteTicks": usage.ri_system_time,
  "timebaseNumerator": timebase.numer,
  "timebaseDenominator": timebase.denom,
  "userCpuSeconds": Double(usage.ri_user_time) * secondsPerTick,
  "systemCpuSeconds": Double(usage.ri_system_time) * secondsPerTick,
  "residentBytes": usage.ri_resident_size,
  "physicalFootprintBytes": usage.ri_phys_footprint,
  "lifetimeMaximumPhysicalFootprintBytes": usage.ri_lifetime_max_phys_footprint,
  "packageIdleWakeups": usage.ri_pkg_idle_wkups,
  "interruptWakeups": usage.ri_interrupt_wkups
]
let data = try JSONSerialization.data(withJSONObject: sample, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
