# 🔒 MemoSafe (Memo App)

[![Flutter Version](https://img.shields.io/badge/Flutter-3.10%2B-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart Version](https://img.shields.io/badge/Dart-3.10%2B-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Security](https://img.shields.io/badge/Encryption-AES--256--CBC%20%7C%20SQLCipher-red?style=for-the-badge&logo=auth0&logoColor=white)](#-security--encryption-architecture)
[![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)
[![Platforms](https://img.shields.io/badge/Platforms-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Desktop-blueviolet?style=for-the-badge)](#-platform-support)

> **MemoSafe** is an enterprise-grade, privacy-first cross-platform notebook and secure vault application built with Flutter. Engineered with hardware-backed encryption, SQLCipher encrypted SQLite databases, biometric authentication, multi-modal notes (text, checklists, voice memos, freehand drawings, image attachments), and real-time Firebase cloud synchronization.

---

## 📋 Table of Contents

- [✨ Core Features](#-core-features)
- [🔒 Security & Encryption Architecture](#-security--encryption-architecture)
- [🏗 System Architecture](#-system-architecture)
- [📱 Multi-Modal Note Types](#-multi-modal-note-types)
- [📁 Directory Structure](#-directory-structure)
- [🚀 Getting Started](#-getting-started)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
  - [Firebase Setup](#firebase-setup)
  - [Platform-Specific Configurations](#platform-specific-configurations)
- [🧪 Testing & Verification](#-testing--verification)
- [🛠 Built With](#-built-with)
- [🤝 Contributing](#-contributing)
- [📄 License](#-license)

---

## ✨ Core Features

### 🔐 Zero-Trust Security & Vault
- **Hardware-Backed Encryption**: Master encryption keys are randomly generated and securely stored in Android Keystore / iOS Keychain via `flutter_secure_storage`.
- **Encrypted Local Storage**: SQLite database encrypted via **SQLCipher** (AES-256).
- **Binary Attachment Encryption**: Images, drawings, and voice recordings encrypted with AES-256-CBC and random 16-byte initialization vectors (IV).
- **Biometric Unlock & PIN Security**: Protect private notes in a dedicated **Vault** using fingerprint/Face ID (`local_auth`) or secure SHA-256 hashed PIN locks.

### 📝 Rich Multi-Modal Notes
- **Text & Rich Content**: Instant note creation with full-text search across titles and body contents.
- **Interactive Checklists**: Manage tasks with real-time completion tracking and dynamic list items.
- **Audio Voice Memos**: In-app audio recorder and player with secure local file encryption.
- **Freehand Canvas Drawing**: Custom vector drawing canvas with adjustable brush sizes, color palette selection, stroke history, and encrypted storage.
- **Media Attachments**: High-resolution image attachments with built-in full-screen zoomable viewer.

### 🔄 Seamless Sync & UX
- **Firebase Multi-Device Sync**: Automatic background sync of notes, vault configurations, and user preferences via Cloud Firestore and Firebase Auth (Email/Password & Google Sign-In).
- **Flexible Note Organization**: Pin important notes, sort by creation date, or arrange manually using custom drag-and-drop ordering.
- **Archive & Vault Workflows**: Instantly archive completed notes or move confidential notes into the encrypted Vault.
- **Unsaved Changes Protection**: Built-in modal safeguards preventing accidental loss of uncommitted edits.
- **Dynamic Theming**: Responsive Light Mode and OLED Pitch-Black Dark Mode with custom typography support.

---

## 🔒 Security & Encryption Architecture

MemoSafe employs a multi-layered defense-in-depth security model to guarantee data privacy both at rest and in transit.

```
┌─────────────────────────────────────────────────────────────────┐
│                      User Authentication                        │
│             (Firebase Auth / Biometrics / PIN)                  │
└────────────────────────────────┬────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                 Hardware Secure Storage (256-bit)                │
│             (Android Keystore / iOS Keychain)                   │
└────────────────────────────────┬────────────────────────────────┘
                                 │
                 ┌───────────────┴───────────────┐
                 ▼                               ▼
  ┌─────────────────────────────┐ ┌─────────────────────────────┐
  │   SQLCipher Database Key    │ │  AES-256 Attachment Key     │
  └──────────────┬──────────────┘ └──────────────┬──────────────┘
                 │                               │
                 ▼                               ▼
  ┌─────────────────────────────┐ ┌─────────────────────────────┐
  │  Encrypted notes.db (SQLite)│ │ Encrypted Files (Media/Audio)│
  └─────────────────────────────┘ └─────────────────────────────┘
```

### Encryption Breakdown
1. **Master Key Generation**: On initial launch, `SecurityService` generates a 256-bit (32-byte) cryptographically secure random key using `Random.secure()`.
2. **Key Protection**: Key is written to OS secure hardware storage (`AndroidOptions` / `IOSOptions(accessibility: KeychainAccessibility.first_unlock)`).
3. **Database Security**: SQLite database (`notes.db`) is locked with `sqflite_sqlcipher`. Data on disk is completely inaccessible without the hardware master key.
4. **Attachment Encryption**: Files stored in local storage are encrypted with AES-256-CBC (`encrypt` package). Each binary payload is prepended with a unique 16-byte random IV.
5. **Vault Protection**: Vault access requires passing biometric verification (`local_auth`) or matching the SHA-256 salted PIN hash backed up securely in both hardware storage and Firestore.

---

## 🏗 System Architecture

The project follows a clean separation of concerns leveraging service singletons and reactive state builders:

- **`DBHelper`**: Manages encrypted SQLite table creation, schema migrations (v1 to v8), custom queries, sorting, and user-isolated multi-tenant data access.
- **`SecurityService`**: Handles hardware key generation, secure storage read/write, file/bytes encryption/decryption, and PIN hash calculation.
- **`FirestoreService`**: Manages remote cloud persistence, snapshot parsing, conflict mitigation, timestamp normalization, and remote backup of vault hashes.
- **`AuthService`**: Encapsulates Firebase Authentication workflows (Email/Password & Google Sign-In) and session management.
- **`ThemeController`**: Controls reactive theme state (`ThemeNotifier`) persisting user preferences across app restarts.

---

## 📱 Multi-Modal Note Types

| Note Type | Storage Format | Features | Security |
| :--- | :--- | :--- | :--- |
| 📄 **Text Note** | `title`, `desc` fields in SQLCipher | Rich text body editing, full-text live search | Encrypted via SQLCipher |
| ☑️ **Checklist** | JSON-encoded item array | Task completion state, item re-ordering | Encrypted via SQLCipher |
| 🎙️ **Audio Note** | Encrypted `.aac`/`.m4a` audio files | High-fidelity recording (`record`), playback controls (`audioplayers`) | Encrypted with AES-256-CBC |
| 🎨 **Drawing Canvas**| JSON stroke vector paths | Multi-color palette, brush sizes, clear/undo controls | Encrypted stroke payload |
| 🖼️ **Image Gallery**| Encrypted binary image files | Multi-image selection (`image_picker`), custom interactive viewer | Encrypted with AES-256-CBC |

---

## 📁 Directory Structure

```
memo_app/
├── android/                  # Android native project configuration
├── ios/                      # iOS native project configuration
├── assets/                   # Static assets (fonts, icons, default images)
│   ├── fonts/                # Custom typography (e.g. Rosemary.ttf)
│   └── icon/                 # Application icon assets
├── lib/
│   ├── firebase_options.dart # Platform-specific Firebase credentials
│   ├── main.dart             # App entry point, MaterialApp theme & AuthGate
│   └── helper_pages/
│       ├── archive_page.dart         # Archived notes view
│       ├── audio_clip.dart           # Audio playback component
│       ├── auth_service.dart         # Authentication service provider
│       ├── biometric_service.dart    # Fingerprint & Face ID integration
│       ├── checklist_item.dart       # To-do checklist model & UI widget
│       ├── db_helper.dart            # Encrypted SQLite database engine
│       ├── drawing_canvas.dart       # Freehand drawing canvas widget
│       ├── firestore_service.dart    # Cloud sync service
│       ├── home_page.dart            # Main dashboard & notes grid
│       ├── image_viewer_page.dart    # Full-screen image viewer
│       ├── login_page.dart           # Authentication & sign-in screen
│       ├── note_card.dart            # Responsive note preview tile widget
│       ├── note_detail_page.dart     # Comprehensive multi-modal note editor
│       ├── note_type.dart            # Models & enums for Note types and statuses
│       ├── pin_entry_dialog.dart     # PIN creation and unlock dialogs
│       ├── pin_service.dart          # PIN hashing and validation logic
│       ├── security_service.dart     # Encryption engine & secure storage interface
│       ├── theme_controller.dart     # Light/Dark mode state management
│       └── vault_page.dart           # Protected Vault interface
└── test/                     # Unit, integration, and widget tests
    ├── pin_service_test.dart
    ├── security_test.dart
    └── unsaved_changes_test.dart
```

---

## 🚀 Getting Started

### Prerequisites

Before building MemoSafe, ensure you have the following installed:

- **Flutter SDK**: `>= 3.10.7` ([Install Guide](https://docs.flutter.dev/get-started/install))
- **Dart SDK**: `>= 3.10.7`
- **Android Studio** (for Android build) / **Xcode 14+** (for iOS build)
- **Git**

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/Gamvir-Khanal/MemoSafe.git
   cd MemoSafe
   ```

2. **Install Flutter dependencies:**
   ```bash
   flutter pub get
   ```

3. **Verify Flutter environment:**
   ```bash
   flutter doctor
   ```

### Firebase Setup

1. Create a Firebase project in the [Firebase Console](https://console.firebase.google.com/).
2. Enable **Authentication** (Email/Password and Google Sign-In methods).
3. Enable **Cloud Firestore Database**.
4. Configure Firebase for your project using the FlutterFire CLI:
   ```bash
   npm install -g firebase-tools
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
   This will generate/update `lib/firebase_options.dart`.

### Platform-Specific Configurations

#### Android Setup (`android/app/build.gradle.kts`)
- Minimum SDK Version: `21`
- Ensure permissions in `android/app/src/main/AndroidManifest.xml`:
  ```xml
  <uses-permission android:name="android.permission.USE_BIOMETRIC"/>
  <uses-permission android:name="android.permission.RECORD_AUDIO"/>
  <uses-permission android:name="android.permission.INTERNET"/>
  ```

#### iOS Setup (`ios/Runner/Info.plist`)
Add privacy usage descriptions for biometric authentication, microphone, and photo gallery:
```xml
<key>NSFaceIDUsageDescription</key>
<string>MemoSafe uses Face ID to secure your private vault notes.</string>
<key>NSMicrophoneUsageDescription</key>
<string>MemoSafe requires microphone access to record audio notes.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>MemoSafe requires photo library access to attach images to notes.</string>
```

---

## 🧪 Testing & Verification

Run the test suite to verify security services, PIN hashing, and UI safeguards:

```bash
# Run all unit and widget tests
flutter test

# Run tests with coverage output
flutter test --coverage
```

### Covered Test Specifications
- `pin_service_test.dart`: Validates PIN verification, error handling, and hash generation.
- `security_test.dart`: Verifies encryption key generation and payload cryptography.
- `unsaved_changes_test.dart`: Tests form dirtiness detection and back-navigation confirmation logic.

---

## 🛠 Built With

- **[Flutter](https://flutter.dev/)** - Modern UI Toolkit for Mobile, Desktop & Web
- **[SQLCipher](https://www.zetetic.net/sqlcipher/) / [sqflite_sqlcipher](https://pub.dev/packages/sqflite_sqlcipher)** - 256-bit AES SQLite encryption
- **[flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage)** - Hardware-backed secure keystore & keychain interface
- **[encrypt](https://pub.dev/packages/encrypt)** - AES-256-CBC cryptography
- **[local_auth](https://pub.dev/packages/local_auth)** - Biometric authentication (Fingerprint / Face ID)
- **[Firebase](https://firebase.google.com/)** - Auth (`firebase_auth`, `google_sign_in`) & Cloud Firestore (`cloud_firestore`)
- **[record](https://pub.dev/packages/record)** & **[audioplayers](https://pub.dev/packages/audioplayers)** - Voice recording & audio playback

---

## 🤝 Contributing

Contributions are welcome! If you find a bug or want to introduce a feature:

1. Fork the Project.
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`).
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`).
4. Push to the Branch (`git push origin feature/AmazingFeature`).
5. Open a Pull Request.

---

## 📄 License

Distributed under the MIT License. See `LICENSE` for more information.

---

<p center>Made with ❤️ by Gamvir Khanal</p>
