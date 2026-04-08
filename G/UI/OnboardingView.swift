import SwiftUI

/// First-launch onboarding — gets the API key and explains what G can do.
struct OnboardingView: View {
    @Binding var isPresented: Bool
    @ObservedObject private var settings = Settings.shared
    @State private var apiKeyInput = ""
    @State private var currentPage = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                // Page 1: Welcome
                welcomePage.tag(0)
                // Page 2: What G can do
                capabilitiesPage.tag(1)
                // Page 3: API Key
                apiKeyPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
        }
        .background(Color.gPrimary)
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("G")
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .foregroundColor(.gAccent)

            Text("Your AI Phone Assistant")
                .font(.title2)
                .foregroundColor(.white)

            Text("Ask me anything. I'll check your messages,\ncalendar, contacts, and more.")
                .multilineTextAlignment(.center)
                .foregroundColor(.gTextDim)

            Spacer()

            Button("Get Started") {
                withAnimation { currentPage = 1 }
            }
            .buttonStyle(GButtonStyle())
            .padding(.bottom, 40)
        }
        .padding()
    }

    private var capabilitiesPage: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("What I Can Do")
                .font(.title2.bold())
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 16) {
                CapabilityRow(icon: "message", text: "Read & send messages")
                CapabilityRow(icon: "calendar", text: "Check & create calendar events")
                CapabilityRow(icon: "person.crop.circle", text: "Search your contacts")
                CapabilityRow(icon: "checklist", text: "Manage reminders & tasks")
                CapabilityRow(icon: "mic", text: "Voice commands — talk to me")
                CapabilityRow(icon: "sparkles", text: "Answer questions with AI")
            }
            .padding(.horizontal, 32)

            Spacer()

            Button("Next") {
                withAnimation { currentPage = 2 }
            }
            .buttonStyle(GButtonStyle())
            .padding(.bottom, 40)
        }
        .padding()
    }

    private var apiKeyPage: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "key")
                .font(.system(size: 40))
                .foregroundColor(.gAccent)

            Text("Connect to Claude")
                .font(.title2.bold())
                .foregroundColor(.white)

            Text("G uses Claude AI for reasoning.\nPaste your API key from console.anthropic.com")
                .multilineTextAlignment(.center)
                .foregroundColor(.gTextDim)

            TextField("sk-ant-...", text: $apiKeyInput)
                .textFieldStyle(.plain)
                .padding()
                .background(Color.gSurface)
                .cornerRadius(12)
                .foregroundColor(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Button("Finish Setup") {
                    if !apiKeyInput.isEmpty {
                        settings.claudeAPIKey = apiKeyInput
                    }
                    isPresented = false
                }
                .buttonStyle(GButtonStyle())
                .disabled(apiKeyInput.isEmpty)

                Button("Skip for now") {
                    isPresented = false
                }
                .foregroundColor(.gTextDim)
            }
            .padding(.bottom, 40)
        }
        .padding()
    }
}

// MARK: - Supporting Views

struct CapabilityRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .foregroundColor(.gAccent)
                .frame(width: 24)
            Text(text)
                .foregroundColor(.white)
        }
    }
}

struct GButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.black)
            .padding(.horizontal, 48)
            .padding(.vertical, 14)
            .background(Color.gAccent)
            .cornerRadius(25)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}
