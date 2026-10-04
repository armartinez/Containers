//
//  ContainerConfiguration.swift
//  Containers
//
//  Local implementation of ContainerConfiguration (replaces ContainerResource.ContainerConfiguration)
//

import ContainerizationOCI
import Foundation

/// Configuration for a container instance.
public struct ContainerConfiguration: Sendable, Codable {

    /// DNS resolver configuration.
    public struct DNSConfiguration: Sendable, Codable {
        public let nameservers: [String]
        public let domain: String?
        public let searchDomains: [String]
        public let options: [String]

        public static let defaultNameservers = ["1.1.1.1"]

        public init(
            nameservers: [String] = defaultNameservers,
            domain: String? = nil,
            searchDomains: [String] = [],
            options: [String] = []
        ) {
            self.nameservers = nameservers
            self.domain = domain
            self.searchDomains = searchDomains
            self.options = options
        }
    }

    /// Resource limits for the container.
    public struct Resources: Sendable, Codable {
        public var cpus: Int
        public var memoryInBytes: UInt64
        public var storage: UInt64?

        public init(
            cpus: Int = 2,
            memoryInBytes: UInt64 = 2 * 1024 * 1024 * 1024,
            storage: UInt64? = nil
        ) {
            self.cpus = cpus
            self.memoryInBytes = memoryInBytes
            self.storage = storage
        }
    }

    public var id: String
    public var image: ImageDescription
    public var mounts: [Filesystem] = []
    public var publishedPorts: [PublishPort] = []
    public var publishedSockets: [PublishSocket] = []
    public var labels: [String: String] = [:]
    public var sysctls: [String: String] = [:]
    public var networks: [AttachmentConfiguration] = []
    public var dns: DNSConfiguration?
    public var rosetta: Bool = false
    public var initProcess: ProcessConfiguration
    public var platform: Platform = .current
    public var resources: Resources = Resources()
    public var virtualization: Bool = false
    public var ssh: Bool = false
    public var useInit: Bool = false
    public var readOnly: Bool = false
    public var capabilities: [String] = []
    public var shmSize: UInt64?
    public var stopSignal: String?
    public var creationDate: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id
        case image
        case mounts
        case publishedPorts
        case publishedSockets
        case labels
        case sysctls
        case networks
        case dns
        case rosetta
        case initProcess
        case platform
        case resources
        case virtualization
        case ssh
        case useInit
        case readOnly
        case capabilities
        case shmSize
        case stopSignal
        case creationDate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.image = try container.decode(ImageDescription.self, forKey: .image)
        self.mounts = try container.decodeIfPresent([Filesystem].self, forKey: .mounts) ?? []
        self.publishedPorts = try container.decodeIfPresent([PublishPort].self, forKey: .publishedPorts) ?? []
        self.publishedSockets = try container.decodeIfPresent([PublishSocket].self, forKey: .publishedSockets) ?? []
        self.labels = try container.decodeIfPresent([String: String].self, forKey: .labels) ?? [:]
        self.sysctls = try container.decodeIfPresent([String: String].self, forKey: .sysctls) ?? [:]
        self.networks = try container.decodeIfPresent([AttachmentConfiguration].self, forKey: .networks) ?? []
        self.dns = try container.decodeIfPresent(DNSConfiguration.self, forKey: .dns)
        self.rosetta = try container.decodeIfPresent(Bool.self, forKey: .rosetta) ?? false
        self.initProcess = try container.decode(ProcessConfiguration.self, forKey: .initProcess)
        self.platform = try container.decodeIfPresent(Platform.self, forKey: .platform) ?? .current
        self.resources = try container.decodeIfPresent(Resources.self, forKey: .resources) ?? Resources()
        self.virtualization = try container.decodeIfPresent(Bool.self, forKey: .virtualization) ?? false
        self.ssh = try container.decodeIfPresent(Bool.self, forKey: .ssh) ?? false
        self.useInit = try container.decodeIfPresent(Bool.self, forKey: .useInit) ?? false
        self.readOnly = try container.decodeIfPresent(Bool.self, forKey: .readOnly) ?? false
        self.capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []
        self.shmSize = try container.decodeIfPresent(UInt64.self, forKey: .shmSize)
        self.stopSignal = try container.decodeIfPresent(String.self, forKey: .stopSignal)
        self.creationDate = try container.decodeIfPresent(Date.self, forKey: .creationDate) ?? Date(timeIntervalSince1970: 0)
    }

    public init(id: String, image: ImageDescription, process: ProcessConfiguration) {
        self.id = id
        self.image = image
        self.initProcess = process
    }

    public init() {
        let image = ImageDescription(
            reference: "",
            descriptor: Descriptor(mediaType: "", digest: "", size: 0)
        )
        self.init(id: "", image: image, process: ProcessConfiguration(executable: ""))
    }
}
