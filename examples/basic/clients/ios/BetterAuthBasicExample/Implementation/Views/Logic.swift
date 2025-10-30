import SwiftUI
import BetterAuth

@Observable
class ContentViewLogic {
    let betterAuthClient: BetterAuthClient
    let authenticationKeyStore: ClientRotatingKeyStore
    let accessKeyStore: ClientRotatingKeyStore
    let identityValueStore: ClientValueStore
    let deviceValueStore: ClientValueStore
    let verificationKeyStore: VerificationKeyStore

    var isLoading = false
    var statusMessage = ""
    var state: AppState
    var identityValue = ""
    var deviceValue = ""
    var otherDeviceValue = ""
    var passphraseValue = ""
    var pyOutput = ""
    var rbOutput = ""
    var rsOutput = ""
    var tsOutput = ""

    init(
        betterAuthClient: BetterAuthClient,
        authenticationKeyStore: ClientRotatingKeyStore,
        accessKeyStore: ClientRotatingKeyStore,
        identityValueStore: ClientValueStore,
        deviceValueStore: ClientValueStore,
        verificationKeyStore: VerificationKeyStore,
        initialState: AppState,
        initialStatusMessage: String,
        initialIdentityValue: String,
        initialDeviceValue: String,
        initialPassphraseValue: String,
    ) {
        self.betterAuthClient = betterAuthClient
        self.authenticationKeyStore = authenticationKeyStore
        self.accessKeyStore = accessKeyStore
        self.identityValueStore = identityValueStore
        self.deviceValueStore = deviceValueStore
        self.verificationKeyStore = verificationKeyStore
        self.state = initialState
        self.statusMessage = initialStatusMessage
        self.identityValue = initialIdentityValue
        self.deviceValue = initialDeviceValue
    }

    func handleCreateAccount() async {
        isLoading = true
        statusMessage = "Creating account. Deriving recovery key..."

        do {
            let passphrase = await Passphrase.generate()
            let seed = try await Argon2.deriveBytes(passphrase: passphrase, byteCount: 32)

            // Generate a recovery key and hash
            let recoveryKey = Secp256r1()
            await recoveryKey.seed(seed)
            let recoveryPublicKey = try await recoveryKey.public()
            let hasher = Hasher()
            let recoveryHash = try await hasher.sum(recoveryPublicKey)

            // Call the createAccount function
            try await betterAuthClient.createAccount(recoveryHash)

            // Copy passphrase to clipboard
            UIPasteboard.general.string = passphrase

            statusMessage = "Account created! Recovery passphrase in clipboard."
            identityValue = try identityValueStore.getSync()
            deviceValue = try deviceValueStore.getSync()
            isLoading = false
            state = AppState.created
        } catch {
            authenticationKeyStore.reset()
            statusMessage = "Error: \(error.localizedDescription)"
            isLoading = false
        }
    }

    func handleDeleteAccount() async {
        isLoading = true
        statusMessage = "Deleting account..."

        do {
            try await betterAuthClient.deleteAccount()

            authenticationKeyStore.reset()
            identityValue = ""
            deviceValue = ""
            statusMessage = "Account deleted."
            isLoading = false
            state = AppState.ready
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
            isLoading = false
        }
    }

    func handleRecoverAccount() async {
        isLoading = true
        statusMessage = "Recovering account. Deriving recovery keys..."

        do {
            let seed = try await Argon2.deriveBytes(passphrase: passphraseValue, byteCount: 32)

            let recoveryKey = Secp256r1()
            await recoveryKey.seed(seed)

            let nextPassphrase = await Passphrase.generate()
            let nextSeed = try await Argon2.deriveBytes(passphrase: nextPassphrase, byteCount: 32)

            let nextRecoveryKey = Secp256r1()
            await nextRecoveryKey.seed(nextSeed)

            let nextPublicKey = try await nextRecoveryKey.public()
            let hasher = Hasher()
            let nextRecoveryHash = try await hasher.sum(nextPublicKey)

            try await betterAuthClient.recoverAccount(identityValue, recoveryKey, nextRecoveryHash)

            deviceValue = try await deviceValueStore.get()

            // Copy passphrase to clipboard
            UIPasteboard.general.string = nextPassphrase

            statusMessage = "Account recovered! Next recovery passphrase in clipboard. Other devices unlinked."
            isLoading = false
            state = AppState.created
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
            isLoading = false
        }
    }

    func handleChangeRecoveryPassphrase() async {
        isLoading = true
        statusMessage = "Changing recovery passphrase..."

        do {
            let newPassphrase = await Passphrase.generate()
            let seed = try await Argon2.deriveBytes(passphrase: newPassphrase, byteCount: 32)

            let newRecoveryKey = Secp256r1()
            await newRecoveryKey.seed(seed)

            let newPublicKey = try await newRecoveryKey.public()
            let hasher = Hasher()
            let newRecoveryHash = try await hasher.sum(newPublicKey)

            try await betterAuthClient.changeRecoveryKey(newRecoveryHash)

            // Copy passphrase to clipboard
            UIPasteboard.general.string = newPassphrase

            statusMessage = "Recovery passphrase changed. New passphrase in clipboard."
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func handleEraseCredentials() async {
        isLoading = true
        statusMessage = "Erasing credentials..."

        do {
            authenticationKeyStore.reset()
            try? await identityValueStore.store("")
            try? await deviceValueStore.store("")
            identityValue = ""
            deviceValue = ""

            statusMessage = "Credentials erased."
            isLoading = false
            state = AppState.ready
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
            isLoading = false
        }
    }

    func handleRotateDevice() async {
        isLoading = true
        statusMessage = "Rotating device key..."

        do {
            try await betterAuthClient.rotateDevice()
            statusMessage = "Rotated device key."
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func handleGenerateLinkContainer() async {
        isLoading = true
        statusMessage = "Generating link data..."

        do {
            UIPasteboard.general.string = try await betterAuthClient.generateLinkContainer(identityValue)
            deviceValue = try await deviceValueStore.get()
            statusMessage = "Link data copied to clipboard."
            isLoading = false
            state = AppState.created
        } catch {
            identityValue = ""
            statusMessage = "Error: \(error.localizedDescription)"
            isLoading = false
        }
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

    func handleUnlinkDevice() async {
        isLoading = true
        statusMessage = "Unlinking device..."

        do {
            try await betterAuthClient.unlinkDevice(otherDeviceValue)
            let wasCurrentDevice = (otherDeviceValue == deviceValue)
            otherDeviceValue = ""
            statusMessage = "Device unlinked."
            isLoading = false
            if wasCurrentDevice {
                identityValue = ""
                deviceValue = ""
                try? await authenticationKeyStore.reset()
                state = AppState.ready
            }
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
            isLoading = false
        }
    }

    func handleCreateSession() async {
        isLoading = true
        statusMessage = "Creating session..."

        do {
            try await betterAuthClient.createSession()
            verificationKeyStore.isAuthenticated = true
            statusMessage = "Signed in!"
            isLoading = false
            state = AppState.authenticated
        } catch {
            accessKeyStore.reset()
            statusMessage = "Error: \(error.localizedDescription)"
            isLoading = false
        }
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
        verificationKeyStore.isAuthenticated = false
        verificationKeyStore.clearCache()
        statusMessage = "Session ended."
        isLoading = false
        state = AppState.created
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
