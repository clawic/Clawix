import Foundation

struct ServiceDemandLease: Equatable, Hashable, Identifiable, Sendable {
    let id: UUID
    let services: Set<ClawJSService>
    let reason: ClawJSServiceStartReason
    let consumer: String
}

struct ServiceDemandDebugSnapshot: Equatable, Sendable {
    var activeServices: Set<ClawJSService>
    var consumersByService: [ClawJSService: Set<String>]
}

struct ServiceDemandAcquireResult: Sendable {
    var lease: ServiceDemandLease
    var servicesToStart: Set<ClawJSService>
    var activeServices: Set<ClawJSService>
}

struct ServiceDemandReleaseResult: Sendable {
    var servicesToStop: Set<ClawJSService>
    var activeServices: Set<ClawJSService>
}

actor ServiceDemandBroker {
    private var leases: [UUID: ServiceDemandLease] = [:]
    private var leaseIDsByService: [ClawJSService: Set<UUID>] = [:]

    func acquire(
        services: Set<ClawJSService>,
        reason: ClawJSServiceStartReason,
        consumer: String
    ) -> ServiceDemandAcquireResult {
        let lease = ServiceDemandLease(
            id: UUID(),
            services: services,
            reason: reason,
            consumer: consumer
        )
        if !services.isEmpty {
            leases[lease.id] = lease
        }

        var servicesToStart: Set<ClawJSService> = []
        for service in services {
            let wasInactive = leaseIDsByService[service, default: []].isEmpty
            leaseIDsByService[service, default: []].insert(lease.id)
            if wasInactive {
                servicesToStart.insert(service)
            }
        }

        return ServiceDemandAcquireResult(
            lease: lease,
            servicesToStart: servicesToStart,
            activeServices: activeServices()
        )
    }

    func release(_ lease: ServiceDemandLease) -> ServiceDemandReleaseResult {
        guard let stored = leases.removeValue(forKey: lease.id) else {
            return ServiceDemandReleaseResult(
                servicesToStop: [],
                activeServices: activeServices()
            )
        }

        var servicesToStop: Set<ClawJSService> = []
        for service in stored.services {
            leaseIDsByService[service]?.remove(stored.id)
            if leaseIDsByService[service]?.isEmpty != false {
                leaseIDsByService[service] = nil
                servicesToStop.insert(service)
            }
        }

        return ServiceDemandReleaseResult(
            servicesToStop: servicesToStop,
            activeServices: activeServices()
        )
    }

    func activeServices() -> Set<ClawJSService> {
        Set(leaseIDsByService.keys)
    }

    func consumers(for service: ClawJSService) -> Set<String> {
        let ids = leaseIDsByService[service] ?? []
        return Set(ids.compactMap { leases[$0]?.consumer })
    }

    func debugSnapshot() -> ServiceDemandDebugSnapshot {
        var consumersByService: [ClawJSService: Set<String>] = [:]
        for service in ClawJSService.allCases {
            let consumers = consumers(for: service)
            if !consumers.isEmpty {
                consumersByService[service] = consumers
            }
        }
        return ServiceDemandDebugSnapshot(
            activeServices: activeServices(),
            consumersByService: consumersByService
        )
    }
}
