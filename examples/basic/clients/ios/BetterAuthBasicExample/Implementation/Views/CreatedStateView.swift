import SwiftUI

struct CreatedStateView: View {
    @Binding var isLoading: Bool
    @Binding var showLinkDevicePrompt: Bool
    @Binding var deviceValue: String

    let onCreateSession: () async -> Void
    let onUnlinkDevice: () async -> Void
    let onRotateDevice: () async -> Void
    let onChangeRecoveryPassphrase: () async -> Void
    let onEraseCredentials: () async -> Void
    let onDeleteAccount: () async -> Void

    @State private var showUnlinkDeviceSheet = false

    var body: some View {
        Group {
            Button(action: {
                Task {
                    await onCreateSession()
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

            Button(action: {
                Task {
                    showLinkDevicePrompt = true
                }
            }) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(width: 20, height: 20)
                    }
                    Text("Link another device")
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
                showUnlinkDeviceSheet = true
            }) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(width: 20, height: 20)
                    }
                    Text("Unlink device")
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
            .sheet(isPresented: $showUnlinkDeviceSheet) {
                BottomSheetInputView(
                    title: "Unlink Device",
                    fields: [("Device to unlink", $deviceValue)],
                    actionTitle: "Unlink",
                    isLoading: isLoading,
                    onSubmit: onUnlinkDevice
                )
            }

            Button(action: {
                Task {
                    await onRotateDevice()
                }
            }) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(width: 20, height: 20)
                    }
                    Text("Rotate device credentials")
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
                Task {
                    await onChangeRecoveryPassphrase()
                }
            }) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(width: 20, height: 20)
                    }
                    Text("Change recovery passphrase")
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
                Task {
                    await onEraseCredentials()
                }
            }) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(width: 20, height: 20)
                    }
                    Text("Erase credentials")
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
                Task {
                    await onDeleteAccount()
                }
            }) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(width: 20, height: 20)
                    }
                    Text("Delete account")
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
