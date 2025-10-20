import SwiftUI
import BetterAuth

struct FakeResponse: Codable {
    let wasFoo: String
    let wasBar: String
    let serverName: String
}

class FakeResponseMessage: ServerResponse<[String: Any]> {
    var response: FakeResponse {
        let payload = self.payload as! [String: Any]
        let responseDict = payload["response"] as! [String: Any]
        return FakeResponse(
            wasFoo: responseDict["wasFoo"] as! String,
            wasBar: responseDict["wasBar"] as! String,
            serverName: responseDict["serverName"] as! String
        )
    }

    var serverIdentity: String {
        let payload = self.payload as! [String: Any]
        let access = payload["access"] as! [String: Any]
        return access["serverIdentity"] as! String
    }

    static func parse(_ message: String) throws -> FakeResponseMessage {
        try ServerResponse<[String: Any]>.parse(message) { response, serverIdentity, nonce in
            let msg = FakeResponseMessage(response: response, serverIdentity: serverIdentity, nonce: nonce)
            return msg
        } as! FakeResponseMessage
    }
}

enum AppState {
    case ready
    case created
    case authenticated
}

struct ContentView: View {
    @State private var state = AppState.ready
    @State private var statusMessage = "Ready"
    @State private var isLoading = false
    @State private var recoveryKey: Secp256r1 = { return Secp256r1() }()
    @State private var foo = ""
    @State private var bar = ""
    @State private var pyOutput = ""
    @State private var rbOutput = ""
    @State private var rsOutput = ""
    @State private var tsOutput = ""

    // Create shared verification key store
    private let verificationKeyStore = VerificationKeyStore()

    // Create the BetterAuthClient with real implementations
    private let betterAuthClient: BetterAuthClient

    init() {
        betterAuthClient = BetterAuthClient(
            hasher: Hasher(),
            noncer: Noncer(),
            verificationKeyStore: verificationKeyStore,
            timestamper: Rfc3339Nano(),
            network: PlaceholderNetwork(),
            paths: createDefaultPaths(),
            deviceIdentifierStore: ClientValueStore(),
            identityIdentifierStore: ClientValueStore(),
            accessKeyStore: ClientRotatingKeyStore(),
            authenticationKeyStore: ClientRotatingKeyStore(),
            accessTokenStore: ClientValueStore()
        )
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Better Auth Example")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(statusMessage)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()

            switch(state) {
                case AppState.ready:
                    Button(action: {
                        Task {
                            await handleCreateAccount()
                        }
                    }) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .frame(width: 20, height: 20)
                            }
                            Text("Create account")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isLoading ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(isLoading)
                    .padding(.horizontal)
                case AppState.created:
                    Button(action: {
                        Task {
                            await handleCreateSession()
                        }
                    }) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .frame(width: 20, height: 20)
                            }
                            Text("Create session")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isLoading ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(isLoading)
                    .padding(.horizontal)
                case AppState.authenticated:
                    Button(action: {
                        Task {
                            await handleRefreshSession()
                        }
                    }) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .frame(width: 20, height: 20)
                            }
                            Text("Refresh session")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isLoading ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(isLoading)
                    .padding(.horizontal)

                    TextField("Foo", text: $foo)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.horizontal)

                    TextField("Bar", text: $bar)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.horizontal)

                    Button(action: {
                        Task {
                            await handleTestAppServers()
                        }
                    }) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .frame(width: 20, height: 20)
                            }
                            Text("Test app servers")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isLoading ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(isLoading)
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("py: \(pyOutput)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("rb: \(rbOutput)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("rs: \(rsOutput)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("ts: \(tsOutput)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
            }

            Spacer()
        }
        .padding()
    }

    private func handleCreateAccount() async {
        isLoading = true
        statusMessage = "Creating account..."

        do {
            // Generate a recovery key and hash
            await recoveryKey.generate()
            let recoveryPublicKey = try await recoveryKey.public()
            let hasher = Hasher()
            let recoveryHash = try await hasher.sum(recoveryPublicKey)

            // Call the createAccount function
            try await betterAuthClient.createAccount(recoveryHash)
            statusMessage = "Account created successfully!"
            state = AppState.created
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func handleCreateSession() async {
        isLoading = true
        statusMessage = "Creating session..."

        do {
            try await betterAuthClient.createSession()
            statusMessage = "Signed in!"
            state = AppState.authenticated
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func handleRefreshSession() async {
        isLoading = true
        statusMessage = "Refreshing session..."

        do {
            try await betterAuthClient.refreshSession()
            statusMessage = "Refreshed!"
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func handleTestAppServers() async {
        isLoading = true
        statusMessage = "Testing app servers..."

        await withTaskGroup(of: Void.self) { group in
            for server in ["py", "rb", "rs", "ts"] {
                group.addTask {
                    await self.makeAccessRequest(server: server, foo: self.foo, bar: self.bar)
                }
            }
        }

        statusMessage = "Executed."

        isLoading = false
    }

    private func makeAccessRequest(server: String, foo: String, bar: String) async {
        do {
            // Create request as a dictionary (AccessRequest expects Dictionary or OrderedDictionary)
            let request: [String: String] = [
                "foo": foo,
                "bar": bar
            ]

            // Make the access request with server prefix
            let reply = try await betterAuthClient.makeAccessRequest("app-\(server):/foo/bar", request)

            // Parse the response
            let response = try FakeResponseMessage.parse(reply)

            // Verify the response signature
            let verificationKey = try await verificationKeyStore.get(identity: response.serverIdentity)
            try await response.verify(verificationKey.verifier(), try await verificationKey.public())

            // Extract the response data
            let responseData = response.response
            let output = "wasFoo: \(responseData.wasFoo), wasBar: \(responseData.wasBar), server: \(responseData.serverName)"

            // Update the appropriate output variable based on server
            switch server {
            case "py":
                pyOutput = output
            case "rb":
                rbOutput = output
            case "rs":
                rsOutput = output
            case "ts":
                tsOutput = output
            default:
                break
            }
        } catch {
            let errorMsg = "Error: \(error.localizedDescription)"
            switch server {
            case "py":
                pyOutput = errorMsg
            case "rb":
                rbOutput = errorMsg
            case "rs":
                rsOutput = errorMsg
            case "ts":
                tsOutput = errorMsg
            default:
                break
            }
        }
    }
}

#Preview {
    ContentView()
}
