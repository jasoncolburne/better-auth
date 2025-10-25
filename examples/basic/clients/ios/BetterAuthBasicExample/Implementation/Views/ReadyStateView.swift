import SwiftUI

struct ReadyStateView: View {
    @Binding var isLoading: Bool
    @Binding var identityValue: String
    @Binding var passphraseValue: String
    let onCreateAccount: () async -> Void
    let onGenerateLinkContainer: () async -> Void
    let onRecoverAccount: () async -> Void

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

            TextField("My identity", text: $identityValue)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            Button(action: {
                Task {
                    await onGenerateLinkContainer()
                }
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

            TextField("My recovery passphrase", text: $passphraseValue)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            Button(action: {
                Task {
                    await onRecoverAccount()
                }
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
        }
    }
}
