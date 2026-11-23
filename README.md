# ShakeSafe — Emergency SOS in Your Pocket

**ShakeSafe** is a personal emergency response application designed to help users quickly alert their trusted contacts and share their real-time location during emergencies.

With a simple SOS activation or shake gesture, users can initiate an emergency alert without having to manually type a message or search for their location. The app automatically prepares an SMS containing an emergency message, GPS coordinates, and a clickable Google Maps location link, addressed to the user's saved emergency contact.

### Key Features

- **One-Tap Emergency SOS:** Quickly activate an emergency alert through the SOS interface.
- **Shake-to-Activate:** Trigger the emergency workflow using a phone shake gesture.
- **Live Location Sharing:** Capture GPS coordinates and generate a Google Maps location link.
- **Emergency Contact Management:** Save a trusted contact using an Indian mobile number (+91).
- **Instant SMS Preparation:** Automatically populate the recipient's number and emergency message in the device's messaging application.
- **SOS History:** View previous emergency alert activities and their status.
- **Cross-Platform Support:** Designed for Android and Web.
- **Permission & Error Handling:** Gracefully handles denied location permissions and unavailable GPS.

### Technology Stack

- **Frontend:** Flutter, Dart
- **Backend:** Serverpod 4
- **Database:** PostgreSQL through Serverpod
- **Location Services:** GPS and Google Maps links
- **Platform Integration:** Android intents and Web SMS links
- **Deployment:** Serverpod Cloud

### Problem It Solves

During an emergency, finding a contact, explaining the situation, and sharing an accurate location can waste valuable time. ShakeSafe simplifies this process by bringing emergency contact management, location sharing, and SOS messaging into one accessible application.

### Vision

To make emergency assistance faster, simpler, and more accessible by turning a smartphone into a pocket-sized personal safety companion.
