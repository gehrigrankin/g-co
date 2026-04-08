// swift-tools-version: 5.9
import PackageDescription

// This file documents the SPM dependencies for the project.
// Add these in Xcode: File → Add Package Dependencies

// Dependencies:
// - None required! The app uses only Apple frameworks:
//   - Foundation, SwiftUI, Combine
//   - Speech (speech recognition)
//   - AVFoundation (text-to-speech)
//   - Contacts, ContactsUI
//   - EventKit (calendar + reminders)
//   - MessageUI (compose messages)
//   - Intents, AppIntents (Siri Shortcuts)

// The Claude API client is built with URLSession (no third-party HTTP library needed).
