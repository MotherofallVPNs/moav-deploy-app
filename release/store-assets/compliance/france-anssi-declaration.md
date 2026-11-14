# France: ANSSI encryption declaration

Not legal advice. This file collects what is needed to file the French
declaration for a "means of cryptology" so MoaV Deploy can be listed on the
App Store in France. Items marked **[VERIFY]** were written from memory of
the regulation and of Apple's and ANSSI's pages, and must be checked against
the current official text before filing.

The crypto inventory in section 2 was taken from the source tree at
v0.2.15+18 (`pubspec.yaml`, `pubspec.lock`, `lib/`). Redo it if the
dependencies change before the declaration is sent.

## 1. Why MoaV Deploy needs it

French law treats software that encrypts as a "moyen de cryptologie".

- **Loi n° 2004-575 du 21 juin 2004 (LCEN), article 30.** Using cryptology
  is free. Supplying it in France, importing it, or transferring it from
  another EU member state is free only when the product does nothing but
  authentication or integrity checking. A product that also provides
  confidentiality needs a prior **declaration** to the Prime Minister, in
  practice to ANSSI. Export outside the EU can need an authorisation, which
  is a different procedure. **[VERIFY]** article number and wording.
- **Décret n° 2007-663 du 2 mai 2007.** Sets the procedure: who declares,
  what the file contains, the time limits, and (in its annexes) the
  categories of products that are exempt from any formality. The form
  itself is fixed by an arrêté, last known as the arrêté du 29 janvier 2015.
  **[VERIFY]** the arrêté currently in force.

Publishing an app on the French App Store counts as supplying it in France.

MoaV Deploy falls under the declaration for one reason: it ships its own
SSH implementation. The SSH client is `dartssh2`, written in Dart, with the
ciphers from `pointycastle` and `pinenacl` compiled into the app binary. It
encrypts the session to the user's server (confidentiality), so it is not an
authentication-only product, and it is not just a call into the operating
system's TLS.

This is the same fact that drives Apple's rule. Apple's export compliance
documentation asks for the French declaration when an app uses standard
encryption "instead of, or in addition to" the encryption in Apple's
operating system and is distributed in France. An app that only uses
HTTPS through the OS does not need it. **[VERIFY]** current wording on
Apple's "Complying with Encryption Export Regulations" page; Apple has
changed the France rule before.

Points that could change the conclusion, worth one check each:

- **[VERIFY]** Annex 1 of the décret lists exempt categories. None is
  believed to cover a general-purpose SSH client, but read the list.
- **[VERIFY]** whether free, open-source (MIT) software published on GitHub
  gets any relief. Do not assume it does.
- The declarant is the entity that supplies the app in France, meaning the
  App Store seller of record (the Apple developer account holder).
  **[VERIFY]** how the form handles a declarant established outside France.

## 2. Technical description for ANSSI

The text below is meant to be pasted into the form's technical section or
attached as an annex. A French summary follows in 2.6.

### 2.1 Product

| | |
|---|---|
| Name | MoaV Deploy |
| Version | 0.2.15 (build 18) |
| Type | Mobile application (iOS and Android), built with Flutter |
| Identifier | `org.motherofallvpns.moavdeploy` |
| Publisher | **[fill in: legal name and address of the developer account holder]** |
| Source code | Public, MIT licence: https://github.com/MotherofallVPNs/moav-deploy-app |
| Distribution | Apple App Store, Google Play, direct download |

### 2.2 What the product does

MoaV Deploy is a server administration tool. The user enters the address
and SSH credentials of a server they own or rent, and the app opens an SSH
session to it to install, configure, start, stop and monitor the MoaV
server software.

The app is not a VPN client. It does not encrypt, tunnel or relay the
phone's own network traffic, it does not encrypt the user's files or
messages, and it offers no encryption service to third parties.

### 2.3 Purpose of the cryptography

Cryptography is used only for:

- **(a)** authenticating and protecting the SSH management sessions between
  the app and the user's own servers, including the monitoring dashboard
  reached through that SSH session;
- **(b)** protecting credentials stored on the device (SSH private keys,
  server passwords, the optional passcode), and the optional
  passphrase-protected backup of an SSH key.

Functions provided: authentication, integrity and confidentiality.

### 2.4 Statement on algorithms

All cryptography in MoaV Deploy consists of standard, publicly specified
algorithms, implemented either by the operating system or by published
open-source libraries. The app contains no proprietary, secret or
home-grown cryptographic algorithm and no modified version of a standard
algorithm. The app's own code only calls these libraries; it does not
implement any cipher, hash or key exchange itself.

### 2.5 Components

**A. SSH client (the component that triggers the declaration)**

| | |
|---|---|
| Library | `dartssh2` 4.1.0 (pure Dart, MIT) |
| Primitives from | `pointycastle` 4.0.0 and `pinenacl` 0.6.0 |
| Protocol | SSH-2: RFC 4251 (architecture), RFC 4252 (authentication), RFC 4253 (transport), RFC 4254 (connection) |
| Role | Client only. The app never acts as an SSH server. |
| Use | Remote command execution on the user's server, and local port forwarding to reach the server's monitoring dashboard |

The app uses the library's default algorithm list without changes. The
algorithm actually used in a session is the first one in each list that
the server also supports.

| Function | Algorithms offered | Key size | Reference |
|---|---|---|---|
| Key exchange | `curve25519-sha256` (and the `@libssh.org` alias) | 255-bit curve | RFC 8731, RFC 7748 |
| | `ecdh-sha2-nistp521`, `-nistp384`, `-nistp256` | 521, 384, 256-bit curves | RFC 5656 |
| | `diffie-hellman-group-exchange-sha256` | group chosen by server | RFC 4419 |
| | `diffie-hellman-group14-sha256` | 2048-bit | RFC 8268 |
| Server host key (signature check) | `ssh-ed25519` | 255-bit curve | RFC 8709, RFC 8032 |
| | `rsa-sha2-512`, `rsa-sha2-256` | set by server key | RFC 8332 |
| | `ecdsa-sha2-nistp521`, `-nistp384`, `-nistp256` | 521, 384, 256-bit curves | RFC 5656 |
| Session encryption | `aes256-gcm@openssh.com`, `aes128-gcm@openssh.com` | 256, 128-bit | AES: FIPS 197; GCM: NIST SP 800-38D; OpenSSH PROTOCOL |
| | `chacha20-poly1305@openssh.com` | 256-bit | OpenSSH PROTOCOL.chacha20poly1305 (ChaCha20 and Poly1305 as in RFC 8439) |
| | `aes256-ctr`, `aes128-ctr` | 256, 128-bit | RFC 4344 |
| Integrity (non-AEAD ciphers) | `hmac-sha2-256-etm@openssh.com`, `hmac-sha2-512-etm@openssh.com`, `hmac-sha2-256`, `hmac-sha2-512` | 256, 512-bit | RFC 6668, RFC 2104 |
| | `hmac-sha1` | 160-bit | RFC 4253 |
| User authentication | Public key (Ed25519 by default) or password | | RFC 4252 |

The `dartssh2` package also contains code for older algorithms (AES-CBC,
`hmac-md5`, SHA-1 based Diffie-Hellman groups). They are not in the default
list and the app does not enable them.

**B. SSH key generation**

| | |
|---|---|
| Library | `pinenacl` 0.6.0 |
| Algorithm | Ed25519 key pair (RFC 8032), 256-bit private seed |
| Use | The app can generate the user's SSH login key on the device. The private key is written to the secure store (component D) in OpenSSH format and the public key is installed on the user's server. The user can also import an existing OpenSSH or PEM private key. |

**C. Passphrase-protected SSH key backup**

| | |
|---|---|
| Library | `cryptography` 2.9.0 (declared as `^2.7.0`) |
| Key derivation | PBKDF2 with HMAC-SHA-256 (RFC 8018), 210 000 iterations, 16-byte random salt, 256-bit output |
| Encryption | AES-256-GCM (FIPS 197, NIST SP 800-38D), 12-byte random nonce |
| Use | Optional. Lets the user export one of their own SSH private keys as a text string protected by a passphrase of at least 10 characters, to move it to another of their devices. Nothing is sent anywhere by the app. |

**D. Credentials at rest**

| | |
|---|---|
| Library | `flutter_secure_storage` 11.1.1 |
| iOS | Apple Keychain Services, accessibility "after first unlock, this device only", iCloud sync off. Encryption is done by the operating system (AES-256-GCM, keys held by the Secure Enclave, per Apple's platform security documentation). |
| Android | Values encrypted with AES-256, the key being protected by the Android Keystore. **[VERIFY]** exact cipher mode and key-wrapping scheme for plugin version 11.1.1 with default `AndroidOptions`. |
| Use | SSH private keys, server passwords, server list, app settings. |

**E. Passcode hash**

| | |
|---|---|
| Library | `cryptography` 2.9.0 |
| Algorithm | PBKDF2 with HMAC-SHA-256, 100 000 iterations, 16-byte random salt, 256-bit output |
| Use | Verifying the optional app passcode. Only the salted hash is kept, inside the secure store (D). This is authentication only, nothing is encrypted with it. |

**F. TLS**

| | |
|---|---|
| WebView | `webview_flutter` 4.14.1: the system WebView (WKWebView on iOS, Android System WebView). TLS 1.2 / 1.3 (RFC 5246, RFC 8446) entirely by the operating system. |
| Dart HTTP client | `dart:io` `HttpClient`, whose TLS (1.2 / 1.3) is the BoringSSL library built into the Flutter engine. Used for one request: signing in to the server's Grafana dashboard at a local address that is forwarded through the SSH session (A). The server's self-signed certificate is accepted for that forwarded address only. |
| Use | Displaying the user's own monitoring dashboard. The app has no backend of its own and contacts no publisher-operated server. |

**G. Random numbers**

Salts, nonces and generated passwords use Dart's `Random.secure()`, which
reads from the operating system's cryptographic random generator. Ed25519
key generation uses the generator inside `pinenacl`, also seeded from
`Random.secure()`. **[VERIFY]** the last point in the `pinenacl` source.

**Components with no cryptographic function**

- `local_auth` 3.0.2 (with `local_auth_darwin` 2.0.4, `local_auth_android`
  2.0.10): asks the operating system for Face ID, Touch ID or fingerprint
  confirmation to unlock the app. No keys or algorithms in the app.
- `qr_flutter` 4.1.0: draws QR codes of client configuration links created
  on the server. Encoding only.
- `archive` 4.5.2: builds unencrypted ZIP files for sharing.
- Base64 and JSON encoding (`dart:convert`).
- The VPN protocols named in the user interface (WireGuard and others) run
  on the server. The app holds no implementation of them; it starts and
  stops them over SSH.

### 2.6 Résumé en français

> **MoaV Deploy** (version 0.2.15) est une application mobile (iOS et
> Android) d'administration de serveurs. Elle ouvre une session SSH vers un
> serveur appartenant à l'utilisateur afin d'y installer, configurer et
> superviser le logiciel serveur MoaV. L'application n'est pas un client
> VPN : elle ne chiffre ni ne relaie le trafic réseau du téléphone.
>
> La cryptographie sert uniquement (a) à authentifier et protéger les
> sessions SSH d'administration vers les serveurs de l'utilisateur, et (b) à
> chiffrer les identifiants stockés localement sur l'appareil.
>
> Tous les algorithmes sont standards et publiés, mis en œuvre par le
> système d'exploitation ou par des bibliothèques open source connues.
> L'application ne contient aucun algorithme cryptographique propriétaire
> ou conçu par l'éditeur.
>
> - **SSH-2** (RFC 4251 à 4254), client uniquement, bibliothèque `dartssh2`
>   4.1.0 avec `pointycastle` 4.0.0 et `pinenacl` 0.6.0. Échange de clés :
>   Curve25519, ECDH NIST P-256/P-384/P-521, Diffie-Hellman 2048 bits.
>   Clés d'hôte : Ed25519, RSA (SHA-2), ECDSA. Chiffrement : AES-128/256
>   (GCM, CTR), ChaCha20-Poly1305. Intégrité : HMAC-SHA-2, HMAC-SHA-1.
> - **Génération de clés SSH** : Ed25519 (`pinenacl` 0.6.0).
> - **Sauvegarde de clé protégée par phrase de passe** : PBKDF2-HMAC-SHA-256
>   (210 000 itérations) et AES-256-GCM (`cryptography` 2.9.0).
> - **Stockage local des identifiants** : Trousseau iOS (Keychain) et
>   Android Keystore, AES-256, via `flutter_secure_storage` 11.1.1.
> - **TLS 1.2 / 1.3** : WebView du système et client HTTP de Dart
>   (BoringSSL), pour afficher le tableau de bord du serveur de
>   l'utilisateur.
>
> Le code source est public sous licence MIT :
> https://github.com/MotherofallVPNs/moav-deploy-app

## 3. Filing guide

### Step 1. Decide the App Store order of operations

France can stay out of the availability list for the first release and be
added once the declaration is done (see `export-compliance.md`). Nothing in
this guide blocks the release in other countries.

### Step 2. Get the form

- ANSSI publishes the form on its site, in the regulation section on
  cryptology controls: start at https://cyber.gouv.fr and look for
  "Contrôle réglementaire sur la cryptographie", then "Déclaration".
  **[VERIFY]** exact URL; the site moved from `ssi.gouv.fr` to
  `cyber.gouv.fr` and deep links have changed.
- The same procedure is described on the French administration portal
  (service-public / entreprendre.service-public.fr) under the declaration
  of a means of cryptology. **[VERIFY]** URL.
- The document is one form for both regimes, titled along the lines of
  "Déclaration et demande d'autorisation d'opérations relatives à un moyen
  de cryptologie". Use the declaration part only.
- No fee.

### Step 3. Fill it in

- **Declarant:** legal name, address, contact person, email, phone of the
  App Store seller of record.
- **Product:** name, version and description from 2.1 and 2.2.
- **Operations declared:** supply in France ("fourniture"), plus transfer
  from an EU member state and import if the form asks which apply.
  **[VERIFY]** which boxes fit an app delivered by Apple's store; do not
  tick export authorisation, that is the other regime.
- **Category / functions:** cryptology used for authentication and
  confidentiality (session encryption and encryption of stored
  credentials), standard algorithms only. Use 2.3 and 2.4.
- **Algorithms and key lengths:** the table in 2.5 A, plus B to F.
- **Language:** fill the form in French. The summary in 2.6 is written for
  that. **[VERIFY]** whether an English technical annex is accepted as is.

### Step 4. Attachments

- The technical description (section 2 of this file, exported to PDF).
- A short product presentation: store description and a few screenshots
  from the private `moav-store-assets` repo (`copy/`, `screenshots/`).
- Link to the public source repository and the MIT licence.
- Proof of identity of the declarant if the form asks for it (company
  registration extract, or ID for an individual). **[VERIFY]**
- ANSSI can ask for more, including source code. Here that is a link to
  the tagged release. **[VERIFY]** the time limit for answering such a
  request.

### Step 5. Send it

- By email to ANSSI's cryptology control office. The address last known is
  `controle@ssi.gouv.fr`. **[VERIFY]** on the form itself; use the address
  printed there.
- Postal alternative: ANSSI, 51 boulevard de La Tour-Maubourg, 75700 Paris
  07 SP, France. **[VERIFY]**
- Send signed PDF copies and keep the sent email and any acknowledgement.

### Step 6. Timing

- The declaration has to be filed before the app is supplied in France,
  with one month's notice. **[VERIFY]** the exact period in the décret.
- It is a declaration regime, not an approval regime. ANSSI checks that the
  file is complete and returns an attestation (the form countersigned, or a
  receipt). ANSSI does not grade or approve the cryptography. If nothing
  comes back within the period, the law lets the declarant proceed.
  **[VERIFY]** the silence rule.
- In practice Apple wants a document to upload, so the App Store step waits
  for ANSSI's reply even where the law would not. Earlier filers report a
  few weeks.

### Step 7. App Store Connect

1. App Store Connect, the app, **App Information**, section **App
   Encryption Documentation**. Add documentation and answer the questions
   as in `export-compliance.md` (encryption: yes; proprietary: no; standard
   algorithms in addition to Apple's: yes; available in France: yes).
2. Upload the ANSSI document in the field for the **French encryption
   declaration**. **[VERIFY]** field name and position, Apple renames these
   screens.
3. Apple reviews the upload and issues a compliance code. Put it in
   `ios/Runner/Info.plist` as `ITSEncryptionExportComplianceCode`.
4. `Info.plist` currently sets `ITSAppUsesNonExemptEncryption` to `false`.
   Filing a declaration and uploading encryption documentation says the
   opposite, so set it to `true` in the same change as the code in step 3.
   **[VERIFY]** against Apple's current guidance; this is a decision for
   the release owner, and it is not made in this commit.
5. Add France in **Pricing and Availability**.

### Step 8. Afterwards

- Keep the declaration, ANSSI's reply and this file together.
- A new declaration is needed only when the cryptographic characteristics
  change, for example a new protocol or a new encryption feature, not for
  ordinary app updates. **[VERIFY]**
- Google Play has no equivalent upload. The French declaration covers the
  product, whichever store delivers it. **[VERIFY]**

## 4. Found while taking the inventory

Two things in the source differ from what `export-compliance.md` says or
implies. Neither changes the conclusion above.

- `export-compliance.md` lists `dart:io` under "OS TLS stack". The Dart
  HTTP client uses BoringSSL shipped inside the Flutter engine, which is a
  second piece of bundled standard encryption besides SSH. Section 2.5 F
  describes it correctly.
- `SshConnection.connect` creates the `SSHClient` without a host key
  verification callback, so the server's host key is not pinned or shown to
  the user on first connection. The description in 2.5 A therefore says the
  host key signature is checked, and does not claim that the server's
  identity is pinned. This is a security question for the app, separate
  from the declaration.
