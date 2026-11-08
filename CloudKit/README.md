# Together House: one-time iCloud setup

The Together House keeps who's inside in the app's **public CloudKit database**. Apple runs it, so there's no server to pay for or look after. It has to be switched on once, and its record types published, before the house works for anyone. It takes about 10 minutes.

## 1. Open the container once
1. Go to **https://icloud.developer.apple.com** and sign in with your developer Apple Account.
2. Open **CloudKit Database**, then choose the container **iCloud.com.manraisingh.workdoro**.

Opening it the first time sets the container up. Until then the app gets a "Bad Container" error and shows *"The front door is stuck"*.

## 2. Add the record types (Development)
**Option A: import the schema file** (fastest)
1. In the CloudKit Console, open **Settings → Tokens** and create a **Management Token**. Copy it.
2. In Terminal, save the token. The command asks you to paste it:
   ```bash
   xcrun cktool save-token --type management
   ```
3. Import the schema:
   ```bash
   xcrun cktool import-schema --team-id 77U7WYYQ99 --container-id iCloud.com.manraisingh.workdoro --environment development --file CloudKit/schema.ckdb
   ```

**Option B: by hand in the Console**
1. **Schema → Record Types → +**, name it `HallVisitor`, with the fields `name` (String), `status` (String), `until` (Date/Time), `look` (Int64), `x` (Double), `y` (Double), `spot` (String), `food` (Int64), `emote` (Int64), `emoteAt` (Date/Time), `say` (Int64), `sayAt` (Date/Time) and `seen` (Date/Time).
2. Add a second record type, `HallReport`, with the fields `target` (String) and `name` (String).
3. **Schema → Indexes**, then add:
   - `HallVisitor` → `seen` → **Queryable** and **Sortable**
   - `HallVisitor` → `recordName` → **Queryable**
   - `HallReport` → `target` → **Queryable**
   - `HallReport` → `recordName` → **Queryable**
4. In **Security Roles**, make sure `_world` can **Read** both types and `_icloud` can **Create** them. These are the defaults for public records.

## 3. Publish it to Production
In the CloudKit Console, click **Deploy Schema Changes…** and deploy to **Production**. App Store and TestFlight builds use Production, so the house stays shut for real users until you've done this.

## 4. Try it on your iPhone
1. Run the app from Xcode on your iPhone, signed in to iCloud. Open the Together House, type a name and tap **Come in**.
2. In the Console, under **Records → Public Database → HallVisitor**, query the records. Your record should be there.
3. Close the house with the X. The record goes away, unless you're in the middle of a focus block.

## Moderation: check reports every day
Apple requires apps with user content to act on reports **within 24 hours**, and the Terms of Use promise it.
- In the Console: **Records → Public Database → HallReport**, sorted by creation date.
- Each report has the `target` (visitor id) and the reported `name`.
- To remove someone, delete the `HallVisitor` record whose record name is that `target`.
- A name reported by 2 different people is already hidden for everyone automatically.
- Delete reports once you've dealt with them.

## What's stored
- **HallVisitor** (one per phone, id = a random UUID made by the app): `name`, `look`, `status` (here/focus/rest), `until` (when the block ends), `x`/`y` (where they're standing in the room), `spot` (the seat they're in), `food` (which snack), `emote`/`emoteAt` and `say`/`sayAt` (the last emote and one-tap message, by number from a fixed list), and `seen` (last update, or the end of the focus block).
- **HallReport**: `target`, `name`.

Nothing else is stored: no email, no location and no Apple Account details. CloudKit only keeps an anonymous per-app user id on each record.

## How busy it gets
Each phone in the house reads everyone every 3 seconds, and saves its own record whenever it moves, sits, emotes or speaks (plus every 20 seconds). CloudKit's free public database allowance grows with the number of users, so this is fine for a cozy crowd. If the house ever gets very busy, raise `HallService.poll`.
