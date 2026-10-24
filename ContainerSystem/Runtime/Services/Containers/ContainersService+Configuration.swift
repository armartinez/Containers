//
//  ContainersService+Configuration.swift
//  Containers
//
//  Turns a container configuration into the virtual machine and process LinuxContainer runs.
//
//  Created by Axel Martinez on 2026/10/24.
//

import Containerization
import ContainerizationError
import ContainerizationOCI
import ContainerizationOS
import Foundation
import SystemPackage

extension Filesystem {
    var asMount: Containerization.Mount {
        switch self.type {
        case .tmpfs:
            return .any(
                type: "tmpfs",
                source: self.source,
                destination: self.destination,
                options: self.options
            )
        case .virtiofs:
            return .share(
                source: self.source,
                destination: self.destination,
                options: self.options
            )
        case .block(let format, _, _):
            return .block(
                format: format,
                source: self.source,
                destination: self.destination,
                options: self.options
            )
        case .volume(_, let format, _, _):
            return .block(
                format: format,
                source: self.source,
                destination: self.destination,
                options: self.options
            )
        }
    }

    func isSocket() throws -> Bool {
        if !self.isVirtiofs {
            return false
        }
        let info = try File.info(self.source)

        return info.isSocket
    }
}

extension ContainersService {
    static func configureContainer(
        czConfig: inout LinuxContainer.Configuration,
        config: ContainerConfiguration,
        precomputedMounts: [Containerization.Mount],
        precomputedSockets: [UnixSocketConfiguration]
    ) throws {
        czConfig.cpus = config.resources.cpus
        czConfig.memoryInBytes = config.resources.memoryInBytes
        czConfig.sysctl = config.sysctls
        czConfig.virtualization = config.virtualization

        czConfig.mounts.append(contentsOf: precomputedMounts)
        czConfig.sockets.append(contentsOf: precomputedSockets)

        for publishedSocket in config.publishedSockets {
            let socketConfig = UnixSocketConfiguration(
                source: publishedSocket.containerPath,
                destination: publishedSocket.hostPath,
                permissions: publishedSocket.permissions,
                direction: .outOf
            )
            czConfig.sockets.append(socketConfig)
        }

        if config.ssh, let sshSocket = Foundation.ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"] {
            let socketUrl = URL(fileURLWithPath: sshSocket)
            let socketPath = socketUrl.path(percentEncoded: false)
            let attrs = try? FileManager.default.attributesOfItem(atPath: socketPath)
            let permissions = (attrs?[.posixPermissions] as? NSNumber)
                .map { FilePermissions(rawValue: mode_t($0.intValue)) }
            let socketConfig = UnixSocketConfiguration(
                source: socketUrl,
                destination: URL(fileURLWithPath: "/run/host-services/ssh-auth.sock"),
                permissions: permissions,
                direction: .into
            )
            czConfig.sockets.append(socketConfig)
        }

        czConfig.hostname = config.id

        // Only set DNS if explicitly provided by container configuration
        // Setting DNS causes the framework to write /etc/resolv.conf which fails on read-only rootfs
        // If not set, containers will use the host's DNS via the VM network
        if let dns = config.dns, !dns.nameservers.isEmpty {
            czConfig.dns = DNS(
                nameservers: dns.nameservers,
                domain: dns.domain,
                searchDomains: dns.searchDomains,
                options: dns.options
            )
        }

        try Self.configureInitialProcess(czConfig: &czConfig, config: config)
    }

    private static func configureInitialProcess(
        czConfig: inout LinuxContainer.Configuration,
        config: ContainerConfiguration
    ) throws {
        let process = config.initProcess

        czConfig.process.arguments = [process.executable] + process.arguments
        czConfig.process.environmentVariables = process.environment
        czConfig.process.capabilities = try capabilities(from: config.capabilities)

        if config.ssh, Foundation.ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"] != nil {
            let sshEnvVar = "SSH_AUTH_SOCK"
            let sshGuestPath = "/run/host-services/ssh-auth.sock"

            if !czConfig.process.environmentVariables.contains(where: {
                $0.starts(with: "\(sshEnvVar)=")
            }) {
                czConfig.process.environmentVariables.append("\(sshEnvVar)=\(sshGuestPath)")
            }
        }

        czConfig.process.terminal = process.terminal
        czConfig.process.workingDirectory = process.workingDirectory
        czConfig.process.rlimits = process.rlimits.compactMap {
            guard let kind = try? LinuxRLimit.Kind($0.limit) else { return nil }
            return .init(kind: kind, hard: $0.hard, soft: $0.soft)
        }

        switch process.user {
        case .raw(let name):
            czConfig.process.user = .init(
                uid: 0,
                gid: 0,
                umask: nil,
                additionalGids: process.supplementalGroups,
                username: name
            )
        case .id(let uid, let gid):
            czConfig.process.user = .init(
                uid: uid,
                gid: gid,
                umask: nil,
                additionalGids: process.supplementalGroups,
                username: ""
            )
        }
    }

    private static func capabilities(from names: [String]) throws -> Containerization.LinuxCapabilities {
        let capabilities = try capabilitySet(from: names)

        guard !capabilities.isEmpty else {
            return .allCapabilities
        }

        return Containerization.LinuxCapabilities(capabilities: Array(capabilities))
    }

    private static func capabilitySet(from names: [String]) throws -> Set<CapabilityName> {
        var capabilities: Set<CapabilityName> = []

        for name in names {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmedName.isEmpty else {
                continue
            }

            if trimmedName.uppercased() == "ALL" {
                capabilities.formUnion(CapabilityName.allCases)
            } else {
                capabilities.insert(try CapabilityName(rawValue: trimmedName))
            }
        }

        return capabilities
    }
}
