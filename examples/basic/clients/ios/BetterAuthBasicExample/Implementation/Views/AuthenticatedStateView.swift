import SwiftUI

struct AuthenticatedStateView: View {
    @Binding var isLoading: Bool
    @Binding var foo: String
    @Binding var bar: String
    @Binding var pyOutput: String
    @Binding var rbOutput: String
    @Binding var rsOutput: String
    @Binding var tsOutput: String
    let onRefreshSession: () async -> Void
    let onEndSession: () async -> Void
    let onTestAppServers: () async -> Void

    @State private var showTestAppServersSheet = false

    var body: some View {
        Group {
            Button(action: {
                Task {
                    await onRefreshSession()
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

            Button(action: {
                Task {
                    await onEndSession()
                }
            }) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(width: 20, height: 20)
                    }
                    Text("End session")
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
                showTestAppServersSheet = true
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
            .sheet(isPresented: $showTestAppServersSheet) {
                BottomSheetInputView(
                    title: "Test App Servers",
                    fields: [
                        ("Foo", $foo),
                        ("Bar", $bar)
                    ],
                    actionTitle: "Test",
                    isLoading: isLoading,
                    onSubmit: onTestAppServers
                )
            }

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
    }
}
