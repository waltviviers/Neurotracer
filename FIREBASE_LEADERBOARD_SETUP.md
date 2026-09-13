# Firebase Leaderboard Setup Guide

## Overview
Neurotracer includes a global leaderboard powered by Firebase Realtime Database, allowing players to submit their high scores and compete worldwide.

---

## Prerequisites
- A Google account
- Firebase project (free tier works)
- Flutter SDK with FlutterFire CLI

---

## Setup Steps

### 1. Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Click **"Add project"**
3. Enter **Project name**: `neurotrace` (or your preferred name)
4. Disable **Google Analytics** (not needed)
5. Click **"Create project"**
6. Wait for project creation to complete

### 2. Enable Realtime Database

1. In Firebase Console, go to **Build** → **Realtime Database**
2. Click **"Create Database"**
3. Choose location: Select closest to your target region (US if unsure)
4. Start in **Test mode** (allows reads/writes without authentication)
5. Click **"Enable"**

**IMPORTANT**: Before going to production, update security rules (see step 6)

### 3. Configure Security Rules

Once database is created:

1. Go to **Realtime Database** → **Rules** tab
2. Replace the default rules with:

```json
{
  "rules": {
    "leaderboard": {
      ".read": true,
      ".write": true,
      ".indexOn": ["score"],
      "$entryId": {
        "playerName": {
          ".validate": "newData.isString() && newData.val().length > 0 && newData.val().length <= 30"
        },
        "score": {
          ".validate": "newData.isNumber() && newData.val() >= 0 && newData.val() <= 999999"
        },
        "timestamp": {
          ".validate": "newData.isNumber()"
        }
      }
    }
  }
}
```

3. Click **"Publish"**

These rules:
- Allow anyone to read the leaderboard
- Allow writes to the leaderboard (no auth required)
- Validate data structure and score ranges
- Index by score for efficient queries

### 4. Run FlutterFire Configure

In your project root directory:

```bash
flutter pub global activate flutterfire_cli
flutterfire configure
```

Follow the prompts:
1. Select your Firebase project
2. Select platforms: **Android** (and iOS if needed)
3. This generates `lib/firebase_options.dart` with your config

### 5. Verify Configuration

Check that `lib/firebase_options.dart` was created with your Firebase credentials:

```dart
static const FirebaseOptions android = FirebaseOptions(
  apiKey: 'YOUR_API_KEY',
  appId: 'YOUR_APP_ID',
  messagingSenderId: 'YOUR_SENDER_ID',
  projectId: 'YOUR_PROJECT_ID',
  databaseURL: 'https://YOUR_PROJECT_ID.firebaseio.com',
);
```

---

## Features

### Player Name
- Auto-generates anonymous names (e.g., "CyberGhost427")
- Players can customize their name via the leaderboard screen
- Max 30 characters

### Score Submission
- Scores submitted when player wins in High Score Mode
- Automatically synced to Firebase
- Includes timestamp for verification

### Leaderboard Display
- Shows top 50 global scores
- Displays player rank, name, and score
- Highlights current player's scores
- Refresh button to update from server
- Graceful handling if offline/unavailable

---

## Testing Locally

1. **Build and run the app**:
   ```bash
   flutter run
   ```

2. **Play and complete High Score Mode** to generate a score

3. **Go to leaderboard** by tapping the leaderboard icon in the header

4. **Verify your score** appears in the list

5. **Check Firebase Console**:
   - Go to **Realtime Database**
   - Expand `leaderboard` node
   - Should see entries like:
   ```
   leaderboard
   ├── 1719000000_123456
   │   ├── playerName: "CyberGhost427"
   │   ├── score: 1500
   │   └── timestamp: 1719000000000
   ```

---

## Production Checklist

Before deploying to Play Store:

- [ ] Firebase project created
- [ ] Realtime Database enabled
- [ ] Security rules configured (step 3)
- [ ] FlutterFire configured (`lib/firebase_options.dart` exists)
- [ ] App tested locally with score submission
- [ ] Leaderboard screen working
- [ ] Player names can be customized
- [ ] Offline behavior tested (graceful fallback)

---

## Troubleshooting

### "Permission Denied" When Submitting Score
- **Cause**: Security rules too restrictive
- **Solution**: Check rules allow writes to `/leaderboard/{entryId}`

### Leaderboard Shows "NO SCORES YET"
- **Cause**: No scores submitted yet, or Firebase not initialized
- **Solution**: 
  - Win in High Score Mode to submit a score
  - Check Firebase Console for data

### "Failed to fetch scores"
- **Cause**: Firebase not initialized, wrong config, or offline
- **Solution**:
  - Check `lib/firebase_options.dart` exists and has correct values
  - Verify internet connection
  - Check Firebase Console for database status

### FlutterFire Configure Doesn't Work
- **Cause**: Firebase project or credentials missing
- **Solution**:
  - Verify Firebase project exists at console.firebase.google.com
  - Run `flutterfire configure` again
  - Select correct project from list

---

## Data Structure

Leaderboard entries follow this structure:

```dart
{
  "playerName": "String",      // 1-30 characters
  "score": "Number",           // 0-999999
  "timestamp": "Number"        // milliseconds since epoch
}
```

Entry ID format: `{timestamp}_{hashCode}`
- Example: `1719000000000_1234567`
- Ensures uniqueness and sortability

---

## Monitoring

### In Firebase Console
1. **Realtime Database** → **Data tab**: See all leaderboard entries
2. **Realtime Database** → **Usage tab**: Monitor reads/writes (free tier: 100 connections, 1GB storage)

### Common Metrics
- Scores per day
- Average score
- Active players
- Storage usage (typically <1MB for thousands of scores)

---

## Future Enhancements

Consider adding:
- **Authentication**: Prevent duplicate scores from same user
- **Weekly leaderboards**: Reset and archive weekly scores
- **Friends leaderboard**: Social integration
- **Achievements**: Badges for milestones
- **Seasonal resets**: Rotate leaderboard by month/season
- **Moderation**: Flag suspicious high scores

---

## Cost

Firebase free tier includes:
- **Realtime Database**: 100 simultaneous connections, 1GB storage
- **Bandwidth**: 1GB/month download

Neurotracer typical usage: <100MB/month storage, <100MB/month bandwidth

No cost unless exceeding free tier limits.

---

## Security Notes

- **No authentication**: Anyone can submit scores (anonymous)
- **Test mode rules**: Allow open reads/writes
- **Validation**: Server-side rules prevent invalid data
- **Data**: Only playerName, score, and timestamp stored (no personal info)

For private leaderboards, implement authentication (see Firebase docs).

---

## Support

If issues persist:
1. Check [Firebase Documentation](https://firebase.google.com/docs)
2. Verify FlutterFire setup: `flutterfire configure`
3. Check app logs: `flutter logs`
4. Test with Firebase Console Realtime Database manually
