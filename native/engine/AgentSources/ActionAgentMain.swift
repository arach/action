import ActionCore

@main
struct ActionAgentMain {
    static func main() {
        ActionAgentRuntime.run(arguments: CommandLine.arguments)
    }
}
