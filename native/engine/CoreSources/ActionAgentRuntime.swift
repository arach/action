import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import Darwin
import Foundation
import Network

enum ActionAgentRuntimePermissionState: String {
    case granted
    case denied
}

struct ActionAgentRuntimeState {
    let startedAt = Date()
}

final class ActionAgentRuntimeServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "dev.action.agent.listener")
    private let runtimeState = ActionAgentRuntimeState()
    private let parentProcessID: pid_t?
    private var parentWatchTimer: DispatchSourceTimer?
    private var activeConnections: [ObjectIdentifier: NWConnection] = [:]

    init(port: UInt16, parentProcessID: pid_t?) throws {
        self.parentProcessID = parentProcessID
        let tcpOptions = NWProtocolTCP.Options()
        let websocketOptions = NWProtocolWebSocket.Options()
        websocketOptions.autoReplyPing = true

        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        parameters.defaultProtocolStack.applicationProtocols.insert(websocketOptions, at: 0)
        parameters.allowLocalEndpointReuse = true

        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "ActionAgent", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid port \(port)"])
        }

        listener = try NWListener(using: parameters, on: endpointPort)
    }

    @MainActor
    func run() -> Never {
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let port = self.listener.port?.rawValue ?? 0
                print("ActionAgent listening on ws://\(ActionAgentDefaults.host):\(port)")
            case .failed(let error):
                FileHandle.standardError.write(Data("ActionAgent listener failed: \(error.localizedDescription)\n".utf8))
                exit(1)
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }

        listener.start(queue: queue)
        startParentWatchIfNeeded()
        NSApplication.shared.run()
        exit(0)
    }

    private func handle(connection: NWConnection) {
        let identifier = ObjectIdentifier(connection)
        activeConnections[identifier] = connection

        connection.stateUpdateHandler = { state in
            switch state {
            case .failed(let error):
                _ = error
                connection.cancel()
                self.activeConnections.removeValue(forKey: identifier)
            case .cancelled:
                self.activeConnections.removeValue(forKey: identifier)
            default:
                break
            }
        }

        connection.start(queue: queue)
        receiveNextMessage(on: connection)
    }

    private func receiveNextMessage(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else {
                connection.cancel()
                return
            }

            if let error {
                _ = error
                self.activeConnections.removeValue(forKey: ObjectIdentifier(connection))
                connection.cancel()
                return
            }

            guard let data, !data.isEmpty else {
                self.receiveNextMessage(on: connection)
                return
            }

            Task { [weak self] in
                guard let self else {
                    connection.cancel()
                    return
                }

                let response = await self.processMessage(data)
                self.queue.async {
                    self.send(response: response, on: connection)
                    self.receiveNextMessage(on: connection)
                }
            }
        }
    }

    private func processMessage(_ data: Data) async -> ActionAgentResponse {
        let decoder = JSONDecoder()

        let request: ActionAgentRequest
        do {
            request = try decoder.decode(ActionAgentRequest.self, from: data)
        } catch {
            return ActionAgentResponse(id: "invalid", ok: false, error: "Invalid request: \(error.localizedDescription)")
        }

        guard let method = ActionAgentMethod(rawValue: request.method) else {
            return ActionAgentResponse(id: request.id, ok: false, error: "Unsupported method \(request.method)")
        }

        do {
            let result = try await handle(request: request, method: method)
            return ActionAgentResponse(id: request.id, ok: true, result: result)
        } catch {
            return ActionAgentResponse(id: request.id, ok: false, error: error.localizedDescription)
        }
    }

    private func handle(request: ActionAgentRequest, method: ActionAgentMethod) async throws -> [String: String] {
        switch method {
        case .ping:
            return ["message": "pong", "service": "ActionAgent"]
        case .status:
            return [
                "service": "ActionAgent",
                "pid": String(ProcessInfo.processInfo.processIdentifier),
                "startedAt": ISO8601DateFormatter().string(from: runtimeState.startedAt),
                "methods": ActionAgentMethod.allCases.map(\.rawValue).joined(separator: ","),
            ]
        case .permissionsSnapshot:
            return [
                "accessibility": actionAgentAccessibilityStatus().rawValue,
                "screenRecording": actionAgentScreenRecordingStatus().rawValue,
                "bundlePath": Bundle.main.bundlePath,
            ]
        case .permissionsRequest:
            return [
                "accessibility": actionAgentAccessibilityStatus(prompt: true).rawValue,
                "screenRecording": actionAgentRequestScreenRecording().rawValue,
                "bundlePath": Bundle.main.bundlePath,
            ]
        case .openAccessibilitySettings:
            actionAgentOpenSettingsPane(anchor: "Privacy_Accessibility")
            return ["status": "opened"]
        case .openScreenRecordingSettings:
            actionAgentOpenSettingsPane(anchor: "Privacy_ScreenCapture")
            return ["status": "opened"]
        case .launchApp:
            guard let bundleId = request.params["bundleId"], !bundleId.isEmpty else {
                throw NSError(domain: "ActionAgent", code: 18, userInfo: [NSLocalizedDescriptionKey: "Missing bundleId"])
            }
            try await MainActor.run {
                try ActionNativeAutomation.launchApplication(bundleId: bundleId)
            }
            return ["bundleId": bundleId, "status": "launched"]
        case .activateApp:
            guard let bundleId = request.params["bundleId"], !bundleId.isEmpty else {
                throw NSError(domain: "ActionAgent", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing bundleId"])
            }

            try ActionNativeAutomation.activateApplication(bundleId: bundleId)
            return ["bundleId": bundleId, "status": "activated"]
        case .typeText:
            guard let text = request.params["text"], !text.isEmpty else {
                throw NSError(domain: "ActionAgent", code: 19, userInfo: [NSLocalizedDescriptionKey: "Missing text"])
            }
            try ActionNativeAutomation.typeText(text)
            return ["status": "typed", "detail": text]
        case .setWindowFrame:
            guard let bundleId = request.params["bundleId"], !bundleId.isEmpty else {
                throw NSError(domain: "ActionAgent", code: 4, userInfo: [NSLocalizedDescriptionKey: "Missing bundleId"])
            }
            guard
                let x = request.params["x"].flatMap(Double.init),
                let y = request.params["y"].flatMap(Double.init),
                let width = request.params["width"].flatMap(Double.init),
                let height = request.params["height"].flatMap(Double.init)
            else {
                throw NSError(domain: "ActionAgent", code: 5, userInfo: [NSLocalizedDescriptionKey: "Missing or invalid window frame parameters"])
            }

            try ActionNativeAutomation.setWindowFrame(bundleId: bundleId, rect: CGRect(x: x, y: y, width: width, height: height))
            return ["bundleId": bundleId, "status": "window-framed"]
        case .getWindowFrame:
            guard let bundleId = request.params["bundleId"], !bundleId.isEmpty else {
                throw NSError(domain: "ActionAgent", code: 6, userInfo: [NSLocalizedDescriptionKey: "Missing bundleId"])
            }
            let rect = try ActionNativeAutomation.getWindowFrame(bundleId: bundleId)
            return [
                "bundleId": bundleId,
                "x": String(describing: rect.origin.x),
                "y": String(describing: rect.origin.y),
                "width": String(describing: rect.size.width),
                "height": String(describing: rect.size.height),
                "status": "window-frame",
            ]
        case .calculatorButtons:
            let buttons = try ActionNativeAutomation.calculatorButtons()
            let data = try JSONEncoder().encode(buttons)
            let text = String(decoding: data, as: UTF8.self)
            return ["status": "calculator-buttons", "buttons": text]
        case .clickCalculatorButton:
            guard let label = request.params["label"], !label.isEmpty else {
                throw NSError(domain: "ActionAgent", code: 20, userInfo: [NSLocalizedDescriptionKey: "Missing label"])
            }
            try ActionNativeAutomation.clickCalculatorButton(label: label)
            return ["status": "clicked", "detail": label]
        case .calculatorDisplayValue:
            let value = try ActionNativeAutomation.calculatorDisplayValue()
            return ["status": "calculator-display", "value": value]
        case .recordAppWindow:
            guard #available(macOS 15.0, *) else {
                throw NSError(domain: "ActionAgent", code: 7, userInfo: [NSLocalizedDescriptionKey: "Window recording requires macOS 15.0 or newer."])
            }
            guard let bundleId = request.params["bundleId"], !bundleId.isEmpty else {
                throw NSError(domain: "ActionAgent", code: 8, userInfo: [NSLocalizedDescriptionKey: "Missing bundleId"])
            }
            guard let outputPath = request.params["output"], !outputPath.isEmpty else {
                throw NSError(domain: "ActionAgent", code: 9, userInfo: [NSLocalizedDescriptionKey: "Missing output"])
            }

            return try await ActionRecordingProbeLauncher.launchAppWindow(
                bundleId: bundleId,
                outputPath: outputPath,
                stopSignalPath: request.params["stopFile"],
                finishedSignalPath: request.params["finishedFile"],
                debugLogPath: request.params["debugLog"]
            )
        case .recordRegion:
            guard #available(macOS 15.0, *) else {
                throw NSError(domain: "ActionAgent", code: 10, userInfo: [NSLocalizedDescriptionKey: "Region recording requires macOS 15.0 or newer."])
            }
            guard let outputPath = request.params["output"], !outputPath.isEmpty else {
                throw NSError(domain: "ActionAgent", code: 11, userInfo: [NSLocalizedDescriptionKey: "Missing output"])
            }
            guard
                let x = request.params["x"].flatMap(Double.init),
                let y = request.params["y"].flatMap(Double.init),
                let width = request.params["width"].flatMap(Double.init),
                let height = request.params["height"].flatMap(Double.init)
            else {
                throw NSError(domain: "ActionAgent", code: 12, userInfo: [NSLocalizedDescriptionKey: "Missing or invalid region parameters"])
            }

            return try await ActionRecordingProbeLauncher.launchRegion(
                rect: CGRect(x: x, y: y, width: width, height: height),
                outputPath: outputPath,
                stopSignalPath: request.params["stopFile"],
                finishedSignalPath: request.params["finishedFile"],
                debugLogPath: request.params["debugLog"],
                fps: request.params["fps"].flatMap(Double.init) ?? 15,
                scale: request.params["scale"].flatMap(Double.init) ?? 1
            )
        case .screenshotAppWindow:
            guard let bundleId = request.params["bundleId"], !bundleId.isEmpty else {
                throw NSError(domain: "ActionAgent", code: 13, userInfo: [NSLocalizedDescriptionKey: "Missing bundleId"])
            }
            guard let outputPath = request.params["output"], !outputPath.isEmpty else {
                throw NSError(domain: "ActionAgent", code: 14, userInfo: [NSLocalizedDescriptionKey: "Missing output"])
            }

            try await actionCaptureAppWindowScreenshot(bundleId: bundleId, outputPath: outputPath)
            return ["bundleId": bundleId, "outputPath": outputPath, "status": "screenshot"]
        case .screenshotRegion:
            guard let outputPath = request.params["output"], !outputPath.isEmpty else {
                throw NSError(domain: "ActionAgent", code: 15, userInfo: [NSLocalizedDescriptionKey: "Missing output"])
            }
            guard
                let x = request.params["x"].flatMap(Double.init),
                let y = request.params["y"].flatMap(Double.init),
                let width = request.params["width"].flatMap(Double.init),
                let height = request.params["height"].flatMap(Double.init)
            else {
                throw NSError(domain: "ActionAgent", code: 16, userInfo: [NSLocalizedDescriptionKey: "Missing or invalid region parameters"])
            }

            try await actionCaptureRegionScreenshot(rect: CGRect(x: x, y: y, width: width, height: height), outputPath: outputPath)
            return ["outputPath": outputPath, "status": "screenshot"]
        case .screenshotScreen:
            guard let outputPath = request.params["output"], !outputPath.isEmpty else {
                throw NSError(domain: "ActionAgent", code: 17, userInfo: [NSLocalizedDescriptionKey: "Missing output"])
            }

            try actionCaptureScreenScreenshot(outputPath: outputPath)
            return ["outputPath": outputPath, "detail": "main-display", "status": "screenshot"]
        }
    }

    private func send(response: ActionAgentResponse, on connection: NWConnection) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        do {
            let data = try encoder.encode(response)
            let context = NWConnection.ContentContext(identifier: "ActionAgentResponse", metadata: [NWProtocolWebSocket.Metadata(opcode: .text)])
            connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { error in
                _ = error
            })
        } catch {
            FileHandle.standardError.write(Data("ActionAgent encode failed: \(error.localizedDescription)\n".utf8))
        }
    }

    private func startParentWatchIfNeeded() {
        guard let parentProcessID else {
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(2), repeating: .seconds(2))
        timer.setEventHandler {
            if kill(parentProcessID, 0) != 0 {
                exit(0)
            }
        }
        timer.resume()
        parentWatchTimer = timer
    }
}

private func actionAgentAccessibilityStatus(prompt: Bool = false) -> ActionAgentRuntimePermissionState {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(options) ? .granted : .denied
}

private func actionAgentScreenRecordingStatus() -> ActionAgentRuntimePermissionState {
    CGPreflightScreenCaptureAccess() ? .granted : .denied
}

@discardableResult
private func actionAgentRequestScreenRecording() -> ActionAgentRuntimePermissionState {
    if CGPreflightScreenCaptureAccess() {
        return .granted
    }

    return CGRequestScreenCaptureAccess() ? .granted : .denied
}

private func actionAgentOpenSettingsPane(anchor: String) {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
        return
    }

    NSWorkspace.shared.open(url)
}

public enum ActionAgentRuntime {
    @MainActor
    public static func run(arguments: [String]) -> Never {
        let port = parsePort(arguments: arguments) ?? ActionAgentDefaults.port
        let parentProcessID = parseParentProcessID(arguments: arguments)

        do {
            let application = NSApplication.shared
            application.setActivationPolicy(.regular)

            let server = try ActionAgentRuntimeServer(port: port, parentProcessID: parentProcessID)
            return server.run()
        } catch {
            FileHandle.standardError.write(Data("ActionAgent failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func parsePort(arguments: [String]) -> UInt16? {
        guard let index = arguments.firstIndex(of: "--port"), arguments.indices.contains(index + 1) else {
            return nil
        }
        return UInt16(arguments[index + 1])
    }

    private static func parseParentProcessID(arguments: [String]) -> pid_t? {
        guard let index = arguments.firstIndex(of: "--parent-pid"), arguments.indices.contains(index + 1) else {
            return nil
        }
        guard let raw = Int32(arguments[index + 1]) else {
            return nil
        }
        return pid_t(raw)
    }
}
