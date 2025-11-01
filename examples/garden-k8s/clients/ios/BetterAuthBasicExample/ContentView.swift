import SwiftUI
import BetterAuth

struct ContentView: View {
    @State private var logic: ContentViewLogic
    @State private var foo = ""
    @State private var bar = ""
    @State private var showLinkDevicePrompt = false
    @State private var linkContainer = ""

    private var identity: String {
        logic.identityValue.count > 36 ? String(logic.identityValue.dropFirst(36)) : ""
    }

    private var device: String {
        logic.deviceValue.count > 36 ? String(logic.deviceValue.dropFirst(36)) : ""
    }

    init() {
        let verificationKeyStore = VerificationKeyStore(serverLifetimeHours: 12)
        let authenticationKeyStore = ClientRotatingKeyStore(prefix: "authentication")
        let accessKeyStore = ClientRotatingKeyStore(prefix: "access")
        let identityValueStore = ClientValueStore(suffix: "identity")
        let deviceValueStore = ClientValueStore(suffix: "device")

        let betterAuthClient = BetterAuthClient(
            hasher: Hasher(),
            noncer: Noncer(),
            verificationKeyStore: verificationKeyStore,
            timestamper: Rfc3339Nano(),
            network: Network(),
            paths: createDefaultPaths(),
            deviceIdentifierStore: deviceValueStore,
            identityIdentifierStore: identityValueStore,
            accessKeyStore: accessKeyStore,
            authenticationKeyStore: authenticationKeyStore,
            accessTokenStore: ClientValueStore(suffix: "token")
        )

        // Infer app state based on keychain contents
        let hasAuthentication = authenticationKeyStore.isInitialized()
        let hasAccess = accessKeyStore.isInitialized()

        let initialState: AppState
        let initialStatusMessage: String
        let initialIdentityValue: String
        let initialDeviceValue: String

        if hasAccess {
            initialState = .authenticated
            initialIdentityValue = (try? identityValueStore.getSync()) ?? ""
            initialDeviceValue = (try? deviceValueStore.getSync()) ?? ""
            initialStatusMessage = "Authenticated"
        } else if hasAuthentication {
            initialState = .created
            initialIdentityValue = (try? identityValueStore.getSync()) ?? ""
            initialDeviceValue = (try? deviceValueStore.getSync()) ?? ""
            initialStatusMessage = "Account created"
        } else {
            initialState = .ready
            initialIdentityValue = ""
            initialDeviceValue = ""
            initialStatusMessage = "Ready"
        }

        logic = ContentViewLogic(
            betterAuthClient: betterAuthClient,
            authenticationKeyStore: authenticationKeyStore,
            accessKeyStore: accessKeyStore,
            identityValueStore: identityValueStore,
            deviceValueStore: deviceValueStore,
            verificationKeyStore: verificationKeyStore,
            initialState: initialState,
            initialStatusMessage: initialStatusMessage,
            initialIdentityValue: initialIdentityValue,
            initialDeviceValue: initialDeviceValue,
            initialPassphraseValue: ""
        )
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Better Auth Example")
                .font(.largeTitle)
                .fontWeight(.bold)

            if (identity.count > 0) {
                Text("identity: ...\(identity)")
                    .font(.subheadline)
                    .onTapGesture {
                        UIPasteboard.general.string = logic.identityValue
                    }
            }

            if (device.count > 0) {
                Text("device: ...\(device)")
                    .font(.subheadline)
                    .onTapGesture {
                        UIPasteboard.general.string = logic.deviceValue
                    }
            }

            Text(logic.statusMessage)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()

            switch(logic.state) {
                case AppState.ready:
                    ReadyStateView(
                        isLoading: $logic.isLoading,
                        identityValue: $logic.identityValue,
                        passphraseValue: $logic.passphraseValue,
                        onCreateAccount: { await logic.handleCreateAccount() },
                        onGenerateLinkContainer: { await logic.handleGenerateLinkContainer() },
                        onRecoverAccount: { await logic.handleRecoverAccount() }
                    )
                case AppState.created:
                    CreatedStateView(
                        isLoading: $logic.isLoading,
                        showLinkDevicePrompt: $showLinkDevicePrompt,
                        deviceValue: $logic.otherDeviceValue,
                        onCreateSession: { await logic.handleCreateSession() },
                        onUnlinkDevice: { await logic.handleUnlinkDevice() },
                        onRotateDevice: { await logic.handleRotateDevice() },
                        onChangeRecoveryPassphrase: { await logic.handleChangeRecoveryPassphrase() },
                        onEraseCredentials: { await logic.handleEraseCredentials() },
                        onDeleteAccount: { await logic.handleDeleteAccount() }
                    )
                case AppState.authenticated:
                    AuthenticatedStateView(
                        isLoading: $logic.isLoading,
                        foo: $foo,
                        bar: $bar,
                        pyOutput: $logic.pyOutput,
                        rbOutput: $logic.rbOutput,
                        rsOutput: $logic.rsOutput,
                        tsOutput: $logic.tsOutput,
                        onRefreshSession: { await logic.handleRefreshSession() },
                        onEndSession: { await logic.handleEndSession() },
                        onTestAppServers: { await logic.handleTestAppServers(foo: foo, bar: bar) }
                    )
            }

            Spacer()
        }
        .padding()
        .sheet(isPresented: $showLinkDevicePrompt) {
            LinkDevicePromptView(linkContainer: $linkContainer, onSubmit: {
                showLinkDevicePrompt = false
                Task {
                    await logic.handleLinkDevice(linkContainer: linkContainer)
                }
            })
        }
    }
}

#Preview {
    ContentView()
}
