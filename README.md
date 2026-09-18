# Aegis 🛡️

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white)
![Privacy](https://img.shields.io/badge/Privacy-On--Device-success?style=for-the-badge&logo=shield&logoColor=white)
[![Download APK](https://img.shields.io/badge/Download-APK-brightgreen?style=for-the-badge&logo=android)](https://github.com/Raghul-1908/Aegis/releases/latest)

> **A privacy-focused, on-device scam detection application.**

Aegis acts as a personalized, ultra-secure guardian for your smartphone. By leveraging on-device machine learning (TensorFlow Lite / ONNX), Aegis analyzes incoming notifications and messages in real-time to detect potential scams, phishing attempts, and fraudulent activity—**all without your personal data ever leaving your device.**

---

## ✨ Key Features

- **🔒 100% On-Device Processing**: Your privacy is paramount. Aegis uses locally hosted ML models (TFLite/ONNX) to score notifications. No cloud APIs, no data collection.
- **⚡ Real-time Scam Scoring**: Intercepts and analyzes notifications in the background silently, alerting you only when a high-risk scam is detected.
- **🛡️ Biometric Security**: Secure your app and notification history with local biometric authentication (FaceID/TouchID/PIN).
- **🎨 Dynamic Themes**: Customize your experience with multiple theme modes, including AMOLED pure black, deep blue, dark, and light themes.
- **📊 Notification History**: Keep track of analyzed notifications with detailed risk scores and threat categorizations.
- **🔋 Battery Efficient**: Optimized background processing ensures minimal battery drain during continuous protection.

## 📸 Screenshots

<p align="center">
  <img src="assets/ss1%20(1).jpeg" width="22%" alt="Screenshot 1">
  <img src="assets/ss1%20(2).jpeg" width="22%" alt="Screenshot 2">
  <img src="assets/ss1%20(3).jpeg" width="22%" alt="Screenshot 3">
  <img src="assets/ss1%20(4).jpeg" width="22%" alt="Screenshot 4">
</p>

## 🚀 Getting Started

### 📦 Quick Download
The easiest way to install Aegis is to download the latest compiled APK:
- **[Download the Latest APK from GitHub Releases](https://github.com/Raghul-1908/Aegis/releases/latest)**

### 💻 Development & Building from Source

These instructions will get you a copy of the project up and running on your local machine for development.

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Version `^3.11.5` or compatible)
- [Dart SDK](https://dart.dev/get-dart)
- Android Studio / Xcode (for device emulation and build tools)

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/Raghul-1908/Aegis.git
   cd scamshield
   ```

2. **Get dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run the app (Development):**
   ```bash
   flutter run
   ```

4. **Build the Release APK:**
   To generate your own standalone release APK, run:
   ```bash
   flutter build apk --release
   ```
   *The built APK will be located in `build/app/outputs/flutter-apk/app-release.apk`.*

## 🧠 How it Works

Aegis uses a background service to monitor incoming push notifications and text messages. When a notification is received:
1. The text content is extracted locally.
2. The on-device NLP model evaluates the text against known scam patterns and linguistic anomalies.
3. A risk score is generated.
4. If the risk score exceeds a dangerous threshold, Aegis overrides the notification to warn the user instantly.

## 🛠️ Tech Stack

- **Framework**: [Flutter](https://flutter.dev/)
- **Machine Learning**: TensorFlow Lite / ONNX Runtime
- **Local Database**: Sqflite (SQLite)
- **Security**: Local Auth (Biometrics), Flutter Secure Storage, Crypto
- **Background Processing**: Native Platform Channels & Notification Listeners

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! Feel free to check the [issues page](https://github.com/Raghul-1908/Aegis/issues). 

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

---
*Built with ❤️ for a safer, scam-free digital world.*
