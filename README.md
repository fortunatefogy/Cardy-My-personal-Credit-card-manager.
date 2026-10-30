# CardWise AI

Private-first Flutter Android app for managing Indian credit cards and estimating card rewards. It uses an on-device SQLite database; there is no CardWise account or cloud database.

## Run

Install Flutter and Android Studio with an Android SDK, then run:

```powershell
flutter pub get
flutter run
```

## Current features

- Add, edit, deactivate, reactivate, delete, and search saved cards.
- Store card number, expiry date, and CVV encrypted on Android with a key protected by Android Keystore. The database stores the encrypted payload, not those values in plaintext.
- Browse, search, and filter CardTrail's public card catalogue; view source details and prefill a saved card profile.
- Estimate cashback and reward value for a planned purchase using the rates entered by the user.
- Chat about saved card benefits using Google's Gemini 3.5 Flash-Lite free API tier. Configure a personal Google AI Studio API key in AI Assistant settings. The key is encrypted on this device.

## AI chat and privacy

Chat messages and saved card benefit settings are sent to Google's Gemini API to generate replies. Card numbers, expiry dates, CVVs, and private notes are excluded from the prompt. Google states that free-tier content may be used to improve its products; see Google's [Gemini API pricing](https://ai.google.dev/gemini-api/docs/pricing).

Create a key at [Google AI Studio](https://aistudio.google.com/app/apikey) and enter it in the AI Assistant tab. Gemini's free tier has usage limits and requires an internet connection. The app does not contain a shared API key or a CardWise server.

## Catalogue and recommendations

The CardTrail directory and card detail pages are fetched over the phone's internet connection and cached in local SQLite. Directory entries refresh after 24 hours; card details refresh after 14 days. Catalogue content can change, so verify fees and benefits with the issuer.

The current rewards comparison uses the rates entered by the user. It does not fully apply category rules, caps, exclusions, spending thresholds, merchant eligibility, or incremental fees; treat results as estimates. Offers are currently not included in the app.
# Cardy-My-personal-Credit-card-manager.
