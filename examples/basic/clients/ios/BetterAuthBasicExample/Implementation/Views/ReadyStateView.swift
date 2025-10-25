import SwiftUI

struct ReadyStateView: View {
    @Binding var isLoading: Bool
    @Binding var identityValue: String
    @Binding var passphraseValue: String
    let onCreateAccount: () async -> Void
    let onGenerateLinkContainer: () async -> Void
    let onRecoverAccount: () async -> Void

    @State private var showLinkDeviceSheet = false
    @State private var showRecoverAccountSheet = false

    var body: some View {
        Group {
            Button(action: {
                Task {
                    await onCreateAccount()
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

            Button(action: {
                showLinkDeviceSheet = true
            }) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(width: 20, height: 20)
                    }
                    Text("Link this device")
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
            .sheet(isPresented: $showLinkDeviceSheet) {
                BottomSheetInputView(
                    title: "Link This Device",
                    fields: [("My identity", $identityValue)],
                    actionTitle: "Link",
                    isLoading: isLoading,
                    onSubmit: onGenerateLinkContainer
                )
            }

            Button(action: {
                showRecoverAccountSheet = true
            }) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(width: 20, height: 20)
                    }
                    Text("Recover Account")
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
            .sheet(isPresented: $showRecoverAccountSheet) {
                BottomSheetInputView(
                    title: "Recover Account",
                    fields: [
                        ("My identity", $identityValue),
                        ("Recovery passphrase", $passphraseValue)
                    ],
                    actionTitle: "Recover",
                    isLoading: isLoading,
                    onSubmit: onRecoverAccount
                )
            }
        }
    }
}
