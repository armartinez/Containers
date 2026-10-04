//
//  HTTP2ConnectBufferingHandler.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/09.
//

import NIOCore

/// Buffers incoming bytes until the gRPC HTTP/2 pipeline is configured.
final class HTTP2ConnectBufferingHandler:
    ChannelDuplexHandler, RemovableChannelHandler
{
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private var removalScheduled = false
    private var bufferedReads: [NIOAny] = []

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        bufferedReads.append(data)
    }

    func channelReadComplete(context: ChannelHandlerContext) {}

    func flush(context: ChannelHandlerContext) {
        if !removalScheduled {
            removalScheduled = true
            context.eventLoop.assumeIsolatedUnsafeUnchecked().execute {
                context.pipeline.syncOperations.removeHandler(self, promise: nil)
            }
        }
        context.flush()
    }

    func removeHandler(context: ChannelHandlerContext, removalToken: ChannelHandlerContext.RemovalToken) {
        var didRead = false
        while !bufferedReads.isEmpty {
            context.fireChannelRead(bufferedReads.removeFirst())
            didRead = true
        }
        if didRead {
            context.fireChannelReadComplete()
        }
        context.leavePipeline(removalToken: removalToken)
    }
}
