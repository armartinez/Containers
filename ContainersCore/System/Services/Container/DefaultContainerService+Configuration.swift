//
//  DefaultContainerService+Configuration.swift
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

extension DefaultContainerService {
    static func configureContainer(
        czConfig: inout LinuxContainer.Configuration,
        config: ContainerConfiguration,
        precomputedMounts: [Containerization.Mount],
        precomputedSockets: [UnixSocketConfiguration],
        defaultNameservers: [String] = []
    ) throws {
        czConfig.cpus = config.resources.cpus
        czConfig.memoryInBytes = config.resources.memoryInBytes

        var sysctls = config.sysctls
        sysctls["vm.overcommit_memory"] = "1"
        sysctls["vm.max_map_count"] = "262144"
        czConfig.sysctl = sysctls

        czConfig.virtualization = config.virtualization
        czConfig.useInit = config.useInit

        // nil leaves LinuxContainer's own default set in place.
        if let maskedPaths = config.maskedPaths {
            czConfig.maskedPaths = maskedPaths
        }
        if let readonlyPaths = config.readonlyPaths {
            czConfig.readonlyPaths = readonlyPaths
        }

        if let shmSize = config.shmSize {
            for index in czConfig.mounts.indices where czConfig.mounts[index].destination == "/dev/shm" {
                czConfig.mounts[index].options.removeAll { $0.hasPrefix("size=") }
                czConfig.mounts[index].options.append("size=\(shmSize)")
            }
        }

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

        let hostnameSource = config.networks.first?.options.hostname ?? config.id
        czConfig.hostname =
            hostnameSource.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map { String($0) } ?? config.id

        // No nameservers means the network's gateway.
        if let dns = config.dns {
            czConfig.dns = DNS(
                nameservers: dns.nameservers.isEmpty ? defaultNameservers : dns.nameservers,
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
        czConfig.process.capabilities = try capabilities(add: config.capAdd, drop: config.capDrop)

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

    /// The OCI defaults, or none if `capDrop` holds "ALL", then
    /// every capability if `capAdd` holds "ALL" or each one it names, less each one `capDrop` names.
    private static func capabilities(add: [String], drop: [String]) throws -> Containerization.LinuxCapabilities {
        let add = names(add)
        let drop = names(drop)

        var capabilities: Set<CapabilityName> =
            drop.contains("ALL") ? [] : Set(Containerization.LinuxCapabilities.defaultOCICapabilities.effective)

        if add.contains("ALL") {
            capabilities = Set(CapabilityName.allCases)
        } else {
            for name in add {
                capabilities.insert(try CapabilityName(rawValue: name))
            }
        }

        for name in drop where name != "ALL" {
            capabilities.remove(try CapabilityName(rawValue: name))
        }

        return Containerization.LinuxCapabilities(capabilities: Array(capabilities))
    }

    private static func names(_ capabilities: [String]) -> [String] {
        capabilities.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
    }
}
