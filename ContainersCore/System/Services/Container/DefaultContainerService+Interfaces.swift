//
//  DefaultContainerService+Interfaces.swift
//  Containers
//
//  The interfaces containers get on their networks, and the addresses they hold.
//
//  Created by Axel Martinez on 2026/10/24.
//

import Containerization
import ContainerizationError
import ContainerizationExtras
import Foundation

extension DefaultContainerService {
    /// One interface per network the container attaches to, and what the container's snapshot records of each.
    ///
    /// Only the first gets a default route, as only one can.
    func attachInterfaces(for id: String, configuration: ContainerConfiguration) async throws -> [(interface: any Interface, attachment: Attachment)] {
        var attached: [(interface: any Interface, attachment: Attachment)] = []

        do {
            for (index, network) in configuration.networks.enumerated() {
                attached.append(try await attachInterface(for: id, to: network, isPrimary: index == 0))
            }
        } catch {
            releaseInterfaces(for: id)
            throw error
        }

        return attached
    }

    private func attachInterface(for id: String, to network: AttachmentConfiguration, isPrimary: Bool) async throws -> (
        interface: any Interface, attachment: Attachment
    ) {
        let mtu = network.options.mtu ?? 1280
        let hostname = network.options.hostname.isEmpty ? id : network.options.hostname
        let interface: any Interface

        if var vmnetNetwork = try await vmnetNetwork(named: network.network) {
            let created = try isPrimary ? vmnetNetwork.createInterface(id, mtu: mtu) : vmnetNetwork.createInterfaceWithoutGateway(id)

            vmnetNetworks[network.network]?.network = vmnetNetwork
            attachedNetworks[id, default: []].append(network.network)

            guard let created else {
                throw ContainerizationError(.internalError, message: "no interface on network \(network.network)")
            }

            interface = created
        } else {
            let (address, gateway) = try allocateSharedNATAddress(for: id)

            interface = NATInterface(ipv4Address: address, ipv4Gateway: gateway, macAddress: network.options.macAddress, mtu: mtu)
        }

        let attachment = Attachment(
            network: network.network,
            hostname: hostname,
            ipv4Address: interface.ipv4Address,
            ipv4Gateway: interface.ipv4Gateway ?? interface.ipv4Address.gateway,
            ipv6Address: interface.ipv6Address,
            macAddress: interface.macAddress
        )

        return (interface, attachment)
    }

    /// The vmnet network for a stored network, made the first time a container attaches to it.
    ///
    /// - Returns: The network, or `nil` for the built-in one where vmnet can't be used, which then falls back to
    ///   the Mac's shared NAT.
    private func vmnetNetwork(named name: String) async throws -> VmnetNetwork? {
        guard !usesSharedNAT || name != NetworkConfiguration.defaultName else {
            return nil
        }

        guard let configuration = try await networkService.list().first(where: { $0.name == name }) else {
            throw ContainerizationError(.notFound, message: "network \(name) not found")
        }

        // A network deleted and made again under the same name gets a vmnet network of its own.
        if let cached = vmnetNetworks[name], cached.configuration == configuration {
            return cached.network
        }

        do {
            let network = try VmnetNetwork(
                mode: configuration.mode == .hostOnly ? .VMNET_HOST_MODE : .VMNET_SHARED_MODE,
                subnet: configuration.ipv4Subnet,
                prefixV6: configuration.ipv6Subnet
            )

            vmnetNetworks[name] = VmnetEntry(configuration: configuration, network: network)
            log.info("Created network \(name)", metadata: ["subnet": "\(network.subnet)"])

            return network
        } catch  where name == NetworkConfiguration.defaultName {
            log.warning("vmnet unavailable, using the shared NAT for the default network: \(error)")
            usesSharedNAT = true

            return nil
        } catch {
            throw ContainerizationError(.unsupported, message: "network \(name) couldn't be created: \(error)")
        }
    }

    private func allocateSharedNATAddress(for id: String) throws -> (address: CIDRv4, gateway: IPv4Address) {
        let hostNumber = ipAllocations[id] ?? (UInt8(2)...254).first { !ipAllocations.values.contains($0) }

        guard let hostNumber else {
            throw ContainerizationError(.internalError, message: "no available IP addresses")
        }

        ipAllocations[id] = hostNumber

        return (try CIDRv4("192.168.64.\(hostNumber)/24"), try IPv4Address("192.168.64.1"))
    }

    func releaseInterfaces(for id: String) {
        for name in attachedNetworks.removeValue(forKey: id) ?? [] {
            try? vmnetNetworks[name]?.network.releaseInterface(id)
        }

        ipAllocations.removeValue(forKey: id)
    }
}
