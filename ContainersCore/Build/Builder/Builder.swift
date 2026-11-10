//
//  Builder.swift
//  Containers
//
//  Sandboxed version of Builder that implements build protocol without XPC dependencies
//
//  Created by Axel Martinez on 2026/02/09.
//

import Containerization
import ContainerizationArchive
import ContainerizationError
import ContainerizationOCI
import ContainerizationOS
import CryptoKit
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import Logging
import NIO
import NIOCore
import NIOHPACK
import NIOHTTP2
import NIOPosix

/// Builder that uses ImageService instead of XPC-based ClientImage
public struct Builder: Sendable {
    public static let builderContainerId = "buildkit"

    let client:
        Com_Apple_Container_Build_V1_Builder.Client<
            HTTP2ClientTransport.WrappedChannel
        >
    let grpcClient: GRPCClient<HTTP2ClientTransport.WrappedChannel>
    let group: EventLoopGroup
    let builderShimSocket: FileHandle
    let clientTask: Task<Void, any Swift.Error>
    let imageService: any ImageService

    private let logger: Logger

    init(
        socket: FileHandle,
        group: EventLoopGroup,
        imageService: any ImageService
    ) async throws {
        try socket.setSendBufSize(4 << 20)
        try socket.setRecvBufSize(2 << 20)

        // An already-connected socket gives grpc-swift no address to derive an `:authority` from, and newer
        // gRPC-Go shims reject requests without one (grpc-go #9365). The shim doesn't route on it, so any
        // host name does; this is the CLI's.
        var config = HTTP2ClientTransport.WrappedChannel.Config.defaults
        config.http2.authority = Self.builderContainerId

        let transport = try await HTTP2ClientTransport.WrappedChannel.wrapping(config: config) { configure in
            try await withCheckedThrowingContinuation { continuation in
                ClientBootstrap(group: group)
                    .channelInitializer { channel in
                        configure(channel).map { configured in
                            continuation.resume(returning: configured)
                        }
                    }
                    .withConnectedSocket(socket.fileDescriptor)
                    .whenFailure { error in
                        continuation.resume(throwing: error)
                    }
            }
        }
        let grpcClient = GRPCClient(transport: transport)

        self.grpcClient = grpcClient
        self.client = Com_Apple_Container_Build_V1_Builder.Client(wrapping: grpcClient)
        self.group = group
        self.builderShimSocket = socket
        self.imageService = imageService

        var logger = Logger(label: "app.containers.sandboxed-builder")
        logger.logLevel = .info
        self.logger = logger
        self.clientTask = Task {
            do {
                try await grpcClient.runConnections()
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as RPCError where error.code == .unavailable {
                logger.debug("gRPC connection closed: \(error)")
                throw error
            } catch {
                logger.error("gRPC client connection error: \(error)")
                throw error
            }
        }
    }

    public func info() async throws -> InfoResponse {
        var options = CallOptions.defaults
        options.timeout = .seconds(30)
        return try await self.client.info(InfoRequest(), options: options)
    }

    /// Perform a sandboxed build using custom pipeline that handles image resolution
    public func build(_ config: Builder.BuildConfig) async throws {
        let logger = Logger(label: "app.containers.sandboxed-builder.build")
        logger.info("SandboxedBuilder.build() called with buildID: \(config.id)")

        var continuation: AsyncStream<ClientStream>.Continuation?
        let reqStream = AsyncStream<ClientStream> {
            (cont: AsyncStream<ClientStream>.Continuation) in
            continuation = cont
        }
        guard let continuation else {
            throw BuilderError.invalidContinuation
        }

        defer {
            continuation.finish()
        }

        // Terminal handling would go here if needed
        // For now, we skip this as it requires internal TerminalCommand type

        logger.info("Creating gRPC stream to BuildKit")
        logger.info("Build config: buildID=\(config.id), contextDir=\(config.contextDir)")
        logger.info("Build config: dockerfile size=\(config.dockerfile.count) bytes, tags=\(config.tags)")
        logger.info(
            "Build config: platforms=\(config.platforms.map { $0.description }), target=\(config.target)"
        )
        logger.info("Build config: exports=\(config.exports.map { $0.type })")

        logger.info("Initializing sandboxed build pipeline")
        let pipeline = BuildPipeline(
            config: config,
            imageService: self.imageService
        )

        logger.info("Starting pipeline execution")

        // Start a background task to log progress
        let progressTask = Task {
            try? await Task.sleep(for: .seconds(30))
            logger.warning("Pipeline has been running for 30 seconds without completion")
            try? await Task.sleep(for: .seconds(30))
            logger.error("Pipeline has been running for 60 seconds - BuildKit may not be responding")
        }

        do {
            try await self.client.performBuild(
                metadata: try Self.buildMetadata(config),
                options: .defaults,
                requestProducer: { writer in
                    for await message in reqStream {
                        try await writer.write(message)
                    }
                },
                onResponse: { response in
                    try await pipeline.run(sender: continuation, receiver: response.messages)
                }
            )
            progressTask.cancel()
            grpcClient.beginGracefulShutdown()
            clientTask.cancel()
            try await group.shutdownGracefully()
            logger.info("Build completed successfully")
        } catch {
            progressTask.cancel()

            // Check if this is the normal build complete signal
            if let builderError = error as? BuilderError, builderError == .buildComplete {
                grpcClient.beginGracefulShutdown()
                clientTask.cancel()
                try await group.shutdownGracefully()
                logger.info("Build completed successfully")
                return
            }

            logger.error("Pipeline execution failed: \(error)")
            grpcClient.beginGracefulShutdown()
            clientTask.cancel()
            try await group.shutdownGracefully()
            throw error
        }
    }

    static func buildMetadata(_ config: Builder.BuildConfig) throws -> Metadata {
        var metadata = Metadata()
        metadata.addString(config.id, forKey: "build-id")
        metadata.addString(
            URL(fileURLWithPath: config.contextDir).path(percentEncoded: false),
            forKey: "context"
        )
        metadata.addString(config.dockerfile.base64EncodedString(), forKey: "dockerfile")
        metadata.addString(config.terminal != nil ? "tty" : "plain", forKey: "progress")
        metadata.addString(config.target, forKey: "target")

        for tag in config.tags {
            metadata.addString(tag, forKey: "tag")
        }
        for platform in config.platforms {
            metadata.addString(platform.description, forKey: "platforms")
        }
        if config.noCache {
            metadata.addString("", forKey: "no-cache")
        }
        for label in config.labels {
            metadata.addString(label, forKey: "labels")
        }
        for buildArg in config.args {
            metadata.addString(buildArg, forKey: "build-args")
        }
        for output in config.exports {
            metadata.addString(try output.stringValue, forKey: "outputs")
        }
        for cacheIn in config.cacheIn {
            metadata.addString(cacheIn, forKey: "cache-in")
        }
        for cacheOut in config.cacheOut {
            metadata.addString(cacheOut, forKey: "cache-out")
        }

        return metadata
    }
}
