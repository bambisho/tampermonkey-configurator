# Key Findings & Task Notes

## Tampermonkey Managed Storage Provisioning (v5.5+)
Source: https://www.tampermonkey.net/documentation.php?locale=en&q=deploying

**This is the solution for auto-configuring TM settings!**

### How it works:
1. Export a TM config as JSON from Tampermonkey (Dashboard -> Utilities -> Export with settings)
2. Host the JSON file on a web server (even localhost)
3. Set Chrome registry policy under:
   `HKLM\Software\Policies\Google\Chrome\3rdparty\extensions\<TM_EXT_ID>\jsonImport\1`
   with keys: hash, url, haltOnError, installAsSystemScripts

### Registry format for Chrome (stable TM = dhdgffkkebhmkfjojejmpbldmpobfkfo):
```
[HKEY_LOCAL_MACHINE\Software\Policies\Google\Chrome\3rdparty\extensions\dhdgffkkebhmkfjojejmpbldmpobfkfo\jsonImport\1]
"hash"="1:<sha256>"
"url"="http://localhost:PORT/tm.json"
"haltOnError"=dword:00000001
"installAsSystemScripts"=dword:00000000
```

### JSON format (tm.json):
```json
{
  "version": "1",
  "scripts": [
    {
      "name": "Script Name",
      "enabled": true,
      "position": 1,
      "uuid": "...",
      "source": "<base64 encoded script>"
    }
  ],
  "settings": {
    "configMode": 100,  // Advanced
    "logLevel": 80
  }
}
```

### Hash handling:
- Run once with wrong hash, TM logs the correct hash in error
- Copy the "calculated" hash into the policy

### Settings values needed:
- configMode: 100 (Advanced) — currently "Novice"
- Externals Update Interval: "Always"
- Security Page Filter Mode: "Disabled"

## User's Full Feature Request List

### 1. Add UK Address button (amazon.co.uk/a/addresses)
- Same style as German address button
- Need ~300 real UK addresses from OpenStreetMap
- Target page: https://www.amazon.co.uk/a/addresses?ref_=ya_d_c_addr

### 2. Tampermonkey settings automation (MAKE CHANGES button or provisioning)
- Externals -> Update Interval -> Always
- General -> Config Mode -> Advanced
- Security -> Page filter mode -> Disabled -> Save

### 3. Default 80% zoom on specific sites
- https://fraud.cat/
- https://www.amazon.co.uk/

### 4. Bookmarks bar entries
- Name: CHAT, Link: https://www.amazon.co.uk/message-us?origRef=de_poc&muClientName=magus&ref_=de_poc
- Name: Your Orders, Link: https://www.amazon.co.uk/gp/your-account/order-history?ref_=ya_d_c_yo

### 5. Amazon returns condition page auto-fill
- URL pattern: amazon.co.uk returns/condition page
- Answers: Yes, Yes, No, None, Yes (last one conditional/not always visible)
- Then click Continue

### 6. Amazon chat quick reply buttons
- URL: amazon.co.uk/message-us*
- 5 pre-written messages about refund follow-up (40 days):
  1. "Hello, I'd like to check on the status of my refund. The product was returned more than 40 days ago, and I haven't received the payment yet. Could you let me know when it will be processed?"
  2. "Hello, it has now been over 40 days since we returned the product, and the refund still hasn't been issued. Please provide a specific date for when we can expect it to be processed."
  3. "Hi, could you give me an update on our refund? We returned the item over 40 days ago and are still waiting."
  4. "Dear Support Team, I am writing to inquire about the status of our refund. The product was returned more than 40 days ago, yet the refund has not been processed. I would appreciate an update on the expected timeline."
  5. "Hello, this is a follow-up regarding our pending refund. The product was returned over 40 days ago, which exceeds any reasonable processing time. If the refund cannot be issued within the next few business days, please escalate this case or let me know who I can contact directly."

## Existing Script Structure
- File: scripts/amazon-suite.user.js (1038 lines)
- Module 1: Amazon Address Filler (IE addresses for UK, DE addresses for Germany)
- Module 2: Delta Platinum Autofill (delta.alliance.codes login + scenario fill)
- @match: amazon.co.uk/*, amazon.de/*, delta.alliance.codes/*
- PowerShell script: tm-configure.ps1 (handles Chrome policy, extension install, tab opening)
