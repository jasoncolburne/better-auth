import SwiftUI

struct LinkDevicePromptView: View {
    @Binding var linkContainer: String
    var onSubmit: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Link Device")
                .font(.headline)
                .padding(.top)

            Text("Paste the link container from the other device:")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            TextEditor(text: $linkContainer)
                .frame(minHeight: 150)
                .padding(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal)

            HStack(spacing: 12) {
                Button("Cancel") {
                    linkContainer = ""
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray.opacity(0.2))
                .foregroundColor(.primary)
                .cornerRadius(10)

                Button("Link") {
                    onSubmit()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            linkContainer = ""
        }
    }
}
