import SwiftUI
import BetterAuth

@Observable
class ContentViewLogic {
    let betterAuthClient: BetterAuthClient
    let authenticationKeyStore: ClientRotatingKeyStore
    let accessKeyStore: ClientRotatingKeyStore
    let identityValueStore: ClientValueStore
    let verificationKeyStore: VerificationKeyStore
    let recoveryKey: Secp256r1

    var isLoading = false
    var statusMessage = ""
    var state: AppState
    var identityValue = ""
    var pyOutput = ""
    var rbOutput = ""
    var rsOutput = ""
    var tsOutput = ""

    init(
        betterAuthClient: BetterAuthClient,
        authenticationKeyStore: ClientRotatingKeyStore,
        accessKeyStore: ClientRotatingKeyStore,
        identityValueStore: ClientValueStore,
        verificationKeyStore: VerificationKeyStore,
        recoveryKey: Secp256r1,
        initialState: AppState,
        initialStatusMessage: String,
        initialIdentityValue: String
    ) {
        self.betterAuthClient = betterAuthClient
        self.authenticationKeyStore = authenticationKeyStore
        self.accessKeyStore = accessKeyStore
        self.identityValueStore = identityValueStore
        self.verificationKeyStore = verificationKeyStore
        self.recoveryKey = recoveryKey
        self.state = initialState
        self.statusMessage = initialStatusMessage
        self.identityValue = initialIdentityValue
    }

    func handleCreateAccount() async {
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
            identityValue = try identityValueStore.getSync()
            state = AppState.created
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func handleDeleteAccount() async {
        isLoading = true
        statusMessage = "Deleting account..."

        do {
            try await betterAuthClient.deleteAccount()
        } catch {
            //
        }

        authenticationKeyStore.reset()
        state = AppState.ready
        identityValue = ""
        statusMessage = "Account deleted."

        isLoading = false
    }

    func handleGenerateLinkContainer() async {
        isLoading = true
        statusMessage = "Generating link data..."

        do {
            UIPasteboard.general.string = try await betterAuthClient.generateLinkContainer(identityValue)
            state = AppState.created
            statusMessage = "Link data copied to clipboard."
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func handleLinkDevice(linkContainer: String) async {
        isLoading = true
        statusMessage = "Linking device..."

        do {
            try await betterAuthClient.linkDevice(linkContainer)
            statusMessage = "Device linked."
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func handleCreateSession() async {
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

    func handleRefreshSession() async {
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

    func handleEndSession() async {
        isLoading = true
        statusMessage = "Ending session..."

        accessKeyStore.reset()
        statusMessage = "Session ended."
        state = AppState.created

        isLoading = false
    }

    func handleTestAppServers(foo: String, bar: String) async {
        isLoading = true
        statusMessage = "Testing app servers..."

        await withTaskGroup(of: Void.self) { group in
            for server in ["py", "rb", "rs", "ts"] {
                group.addTask {
                    await self.makeAccessRequest(server: server, foo: foo, bar: bar)
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
