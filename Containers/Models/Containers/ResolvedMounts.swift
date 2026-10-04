//
//  ResolvedMounts.swift
//  Containers
//
//  Created by Axel Martinez on 03/08/2026.
//

import ContainerSystem
import Containerization
import Foundation

/// The mounts a container is created with, resolved from what the create
/// sheet drafted. The volumes are only named here: whoever creates the
/// container finds or makes them, since some may not exist yet.
struct ResolvedMounts {
    /// A volume to mount. An empty name asks for a fresh anonymous one.
    struct VolumeRequest {
        let name: String
        let destination: String
    }

    let volumes: [VolumeRequest]

    private let bindMounts: [Filesystem]
    private let temporaryFileSystems: [Filesystem]
    private let options: [String] = []

    init(mounts: [Mount], volumes: [VolumeMount]) throws {
        var bindMounts: [Filesystem] = []
        var temporaryFileSystems: [Filesystem] = []
        var volumeRequests: [VolumeRequest] = []

        var takenTargets = Set<String>()

        func reserve(_ target: String) throws {
            guard takenTargets.insert(target).inserted else {
                throw MountError.duplicateTarget(target)
            }
        }

        for mount in mounts {
            let target = mount.trimmedTarget

            // A row added and then left alone is not a mount.
            guard mount.isTemporary || mount.hostURL != nil || !target.isEmpty
            else {
                continue
            }

            guard !target.isEmpty else {
                throw MountError.targetMissing
            }
            guard target.hasPrefix("/") else {
                throw MountError.targetNotAbsolute
            }
            try reserve(target)

            guard !mount.isTemporary else {
                temporaryFileSystems.append(
                    .tmpfs(destination: target, options: options)
                )
                continue
            }

            guard let source = mount.hostURL, source.path.hasPrefix("/") else {
                throw MountError.sourceNotAbsolute
            }

            bindMounts.append(
                .virtiofs(
                    source: source.path,
                    destination: target,
                    options: options
                )
            )
        }

        for draft in volumes {
            let target = draft.trimmedTarget

            guard !draft.trimmedVolumeName.isEmpty || !target.isEmpty else {
                continue
            }

            guard target.hasPrefix("/") else {
                throw MountError.targetNotAbsolute
            }
            try reserve(target)

            volumeRequests.append(
                VolumeRequest(
                    name: draft.source == .anonymousVolume
                        ? "" : draft.trimmedVolumeName,
                    destination: target
                )
            )
        }

        self.bindMounts = bindMounts
        self.temporaryFileSystems = temporaryFileSystems
        self.volumes = volumeRequests
    }

    /// The mounts in the order the guest takes them: what the host binds in,
    /// then the temporary filesystems, then the volumes. A volume nested under
    /// a bind mount has to follow it, or the bind covers it over.
    ///
    /// `found` holds the volume for each of ``volumes``, in the same order.
    func filesystems(with found: [Volume]) -> [Filesystem] {
        let resolvedVolumes = zip(volumes, found).map { request, volume in
            Filesystem.volume(
                name: volume.name,
                format: volume.format,
                source: volume.source,
                destination: request.destination,
                options: options
            )
        }

        return bindMounts + temporaryFileSystems + resolvedVolumes
    }
}
