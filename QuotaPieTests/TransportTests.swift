import Foundation
import Testing
@testable import QuotaPie

struct TransportTests {
    private func executable(_ script: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("mock-codex")
        try Data(("#!/bin/sh\n" + script).utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        return file
    }

    @Test func realPipesAndHandshake() async throws {
        let file = try executable("""
        IFS= read -r line
        case "$line" in *initialize*) ;; *) exit 1 ;; esac
        printf '%s\\n' '{"id":1,"result":{}}'
        IFS= read -r line
        case "$line" in *initialized*) ;; *) exit 1 ;; esac
        IFS= read -r line
        printf '%s\\n' '{"id":2,"result":{"account":{"type":"chatgpt"}}}'
        IFS= read -r line
        printf '%s\\n' '{"method":"account/rateLimits/updated","params":{"rateLimits":{"primary":{"usedPercent":12}}}}'
        printf '%s' '{"id":3,"result":{"rateLimits":{"primary":'
        printf '%s\\n' '{"usedPercent":37.5,"windowDurationMins":300,"resetsAt":1930947200}}}}'
        while IFS= read -r line; do :; done
        """)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let server = CodexAppServer(executable: file)
        do {
            let snapshot = try await CodexProvider(transport: server).fetchUsage()
            #expect(snapshot.windows.first?.availablePercent == 62.5)
            #expect(await server.latestNotification != nil)
            await server.close()
        } catch { await server.close(); throw error }
    }

    @Test func processTimeout() async throws {
        let file = try executable("""
        while IFS= read -r line; do :; done
        """)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let server = CodexAppServer(executable: file, requestTimeout: 0.05)
        await #expect(throws: UsageFetchError.timeout) { try await server.request(method: "account/read") }
        await server.close()
    }

    @Test func processExit() async throws {
        let file = try executable("exit 1\n")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let server = CodexAppServer(executable: file)
        await #expect(throws: UsageFetchError.processFailed) { try await server.request(method: "account/read") }
        await server.close()
    }

    @Test func sanitizedErrors() async throws {
        let file = try executable("""
        IFS= read -r line
        printf '%s\\n' '{"id":1,"result":{}}'
        IFS= read -r line
        IFS= read -r line
        printf '%s\\n' '{"id":2,"error":{"code":401,"message":"secret-do-not-display"}}'
        while IFS= read -r line; do :; done
        """)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let server = CodexAppServer(executable: file)
        await #expect(throws: UsageFetchError.unauthenticated) { try await server.request(method: "account/read") }
        await server.close()
    }
}
