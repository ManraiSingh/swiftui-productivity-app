# Publishing Workdoro 1.0

Everything in this folder is ready. The steps below need your Apple account, so you do them yourself, about 30 to 45 minutes in all.

## What's in this folder
| File | What it's for |
|---|---|
| `Workdoro-1.0.ipa` | The signed App Store build (version 1.0, build 1). Upload it with the Transporter app if you'd rather not use Xcode. |
| `Screenshots (6.9-inch iPhone)/` | 8 screenshots at 1320 × 2868, numbered in upload order. |
| `App icon 1024.png` | Already built into the app. You only need it for your website. |
| `listing.md` | Name, subtitle, promo text, description, keywords, review notes and answers for every form. |
| `privacy.html` | Your privacy policy page. It must be online before you submit. |

The same build is also in Xcode's Organizer as **"Workdoro 1.0 (1)"**.

---

## Step 1: Put the privacy policy online (required)
Apple needs a public web link to it. The free and simple way is GitHub Pages:
1. Sign in at github.com and create a new **public** repository, for example `workdoro`.
2. Upload `privacy.html`, then rename it to `index.html`.
3. Go to **Settings → Pages → Branch: main → Save**.
4. After a minute your link is `https://YOUR-NAME.github.io/workdoro/`.

Use this link as both the **Privacy Policy URL** and the **Support URL**. The page already ends with your contact email.

## Step 2: Create the app in App Store Connect
1. Go to appstoreconnect.apple.com → **Apps → + → New App**.
2. Fill in:
   - Platform: **iOS**
   - Name: **Workdoro**
   - Primary language: English
   - Bundle ID: **com.manraisingh.workdoro**
   - SKU: `workdoro-1`
   - User access: Full access

## Step 3: Upload the build
**Option A (Xcode):**
1. Open Xcode → **Window → Organizer → Archives**.
2. Select **Workdoro 1.0 (1)** → **Distribute App → App Store Connect → Upload**.
3. Keep the default options and click through.

**Option B (Transporter):** install the free Transporter app from the Mac App Store, sign in, and drag in `Workdoro-1.0.ipa`.

After 10 to 30 minutes the build appears under **TestFlight**. Apple emails you when it's ready.

## Step 4: Test it on your iPhone first (strongly recommended)
1. In **TestFlight**, add yourself as an internal tester.
2. Install the **TestFlight** app on your iPhone and open Workdoro from it.
3. Check these things, which can't be tested on a Mac:
   - Widgets on the home screen, and ticking a task from a widget.
   - The Live Activity and Dynamic Island while you focus.
   - Notifications and the alarm sound.
   - It feels smooth.
   - iCloud, if you have an iPad or second iPhone.

## Step 5: Fill in the App Store page
Everything to paste is in `listing.md`:
- **App Information:**
  - Subtitle: *Your tiny town of productivity*
  - Category: Productivity, with Lifestyle as the secondary
  - Privacy Policy URL from Step 1
- **Pricing and Availability:** Free, all countries.
- **App Privacy:** "Data Not Collected".
- **Age Rating:** answer None to everything, which gives 4+.
- **Version 1.0 page:**
  - Promotional text, description, keywords and Support URL.
  - Drag in the 8 screenshots in their numbered order.
  - Choose the build you uploaded.
  - App Review notes from `listing.md`. No sign-in is needed.
  - Copyright: `2026 Manraisingh`.

## Step 6: Submit
Click **Add for Review → Submit**. Review usually takes 1 to 3 days. When it's approved you can release it straight away or pick a date.

---

### Already done and checked
- The release build signs and exports for the App Store with no warnings.
- iCloud is set to Production, and debugging is switched off.
- 18 out of 18 self-tests pass.
- It's 3 MB and works fully offline.
- No tracking, no ads, and the privacy file is included.
- No encryption questions to answer, because that's already set in the app.
- It's tested on the smallest supported iPhone (SE), and updating keeps all data.
- The save file has a backup, so a damaged file can't wipe someone's town.

### For a future update
Raise the build number in Xcode (target **Mossbrook → General → Build**: 1 → 2), then Archive and upload again.
