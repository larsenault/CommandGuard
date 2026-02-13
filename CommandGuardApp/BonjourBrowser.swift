//  BonjourBrowser.swift
//  CommandGuard
//
//
//  Handles browsing for Bonjour services on the local network.

import Foundation
import Network

// Handles browsing for Bonjour services on the local network.
final class BonjourBrowser {
    // Dedicated queue for Network framework callbacks.
    private let queue = DispatchQueue(label: "CommandGuard.BonjourBrowser")
    // Active browser instance (nil when not browsing).
    private var browser: NWBrowser?
    // Bonjour service type to discover (e.g., _commandguard._tcp).
    private let serviceType: String

    // Configure the browser for a specific service type.
    init(serviceType: String = "_commandguard._tcp") {
        self.serviceType = serviceType
    }

    // Starts browsing and delivers updated service lists to the caller.
    func start(onUpdate: @escaping ([GatewayService]) -> Void) {
        // Use TCP parameters because the gateway will accept TCP connections.
        let parameters = NWParameters.tcp
        // Browse for Bonjour services of the configured type.
        let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: nil)
        let browser = NWBrowser(for: descriptor, using: parameters)

        // Called whenever the set of discovered services changes.
        browser.browseResultsChangedHandler = { results, _ in
            let services = results
                .map { GatewayService(result: $0) }
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            onUpdate(services)
        }

        // If the browser fails, cancel to allow a clean restart.
        browser.stateUpdateHandler = { state in
            if case .failed = state {
                browser.cancel()
            }
        }

        // Hold a strong reference so browsing continues.
        self.browser = browser
        browser.start(queue: queue)
    }

    // Stops browsing and releases resources.
    func stop() {
        browser?.cancel()
        browser = nil
    }
}
