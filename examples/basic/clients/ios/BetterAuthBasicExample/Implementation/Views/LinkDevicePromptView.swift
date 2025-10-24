import SwiftUI

struct LinkDevicePromptView: View {
    @Binding var linkContainer: String
    var onSubmit: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Link Device")
                .font(.title)
                .fontWeight(.bold)

            Text("Paste the link container from the other device:")
                .font(.subheadline)

            TextEditor(text: $linkContainer)
                .frame(minHeight: 200)
                .border(Color.gray, width: 1)
                .padding()

            HStack(spacing: 20) {
                Button("Cancel") {
                    linkContainer = ""
                    dismiss()
                }
                .padding()
                .background(Color.gray)
                .foregroundColor(.white)
                .cornerRadius(10)

                Button("Link") {
                    onSubmit()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .padding()
    }
}
