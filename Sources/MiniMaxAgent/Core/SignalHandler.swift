import Foundation

/// Registers UNIX signal handlers for crash-producing signals (SIGSEGV, SIGABRT).
///
/// On receipt of a fatal signal the handler logs the signal name and number
/// to stderr before resetting the signal disposition to its default and
/// re-raising it, which allows the OS to generate a standard crash report.
///
/// ## Usage
/// Call `SignalHandler.register()` once at application startup, before any
/// background work begins:
/// ```swift
/// SignalHandler.register()
/// ```
public enum SignalHandler {

    // MARK: - Public API

    /// Registers handlers for SIGSEGV and SIGABRT.
    ///
    /// Must be called from the main thread before any concurrent work starts
    /// so that the handler is installed before any thread can trigger a fault.
    public static func register() {
        installHandler(for: SIGSEGV)
        installHandler(for: SIGABRT)
    }

    // MARK: - Private

    private static func installHandler(for signum: Int32) {
        signal(signum) { receivedSignal in
            let name: String
            switch receivedSignal {
            case SIGSEGV: name = "SIGSEGV"
            case SIGABRT: name = "SIGABRT"
            default:      name = "SIG\(receivedSignal)"
            }

            // Use write(2) — async-signal-safe, unlike NSLog or print.
            var message = "[MiniMaxAgent] Fatal signal received: \(name) (\(receivedSignal))\n"
            message.withUTF8 { ptr in
                _ = write(STDERR_FILENO, ptr.baseAddress, ptr.count)
            }

            // Reset to default disposition and re-raise so the OS can write a
            // crash report and the process exits with the correct signal status.
            signal(receivedSignal, SIG_DFL)
            raise(receivedSignal)
        }
    }
}
