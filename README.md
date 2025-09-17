# better-auth

(this may still need a bit of work/review)

# Why

The typical authentication and authorization protocols implemented in software today are rarely
ideal.

Often, authentication and authorization protocols use sharing of secrets to accomplish security.
Those who know, know that this is bad practice. We have simple techniques based on different
cryptographic primitives that allow for a much safer experience.

An example of a poor protocol action would be sending a passphrase or a digest of that passphrase as
proof of account ownership to a backend service. Why? An eavesdropper witnessing this message can
immediately use these credentials to gain access to the account.

A better solution would be to derive an asymmetric key pair from a passphrase and store the public
part with the backend auth service. During authentication, the client can derive the corresponding
private key and sign a message to prove the account owner had knowledge of the passphrase.

This document describes a 'better' authentication protocol based on zero-trust and decentralized
techniques that still provides a balanced user experience and is easy to integrate into existing
infrastructure. For an even more robust (decentralized) solution, consider KERI (Key Event Receipt
Infrastructure), from which concepts in this document have been taken.

Server generated messages are also signed, and valid keys are simply specified at a well known
location. `publicKeyDigest` serves as a lookup key.

# Risks that worry the authentication protocol designer

Here we'll consider what is important to prevent and mitigate for authentication and authorization.

## Credential theft

Stealing a passphrase or key directly.

Mitigations: 
- Hardware-backed, unextractable random seed keys.

## Dictionary

An attack that uses known words, combinations and substitutions to guess passphrases.

Mitigations:
- User education. Longer phrases without special characters are just as secure.

## Rainbow table

A more sophistocated passphrase-based system may store a derivations of passphrases to verify
correctness.

This leaves a vulnerability in the backend datastore itself. If the datastore is exfiltrated, it
is possible that several derivations are computed from a dictionary and then many passphrase
derivations compared to see which match, exposing passphrases of many accounts at once.

Mitigations:
- Unique random salts per account passphrase.

## Brute force

A systematic attack that exhausts all possibilities to succeed.

Mitigations:
- Algorithm choice and strength make brute force attack infeasible.
- Random seed keys and rotation for recovery.

## Quantum

An attack using one of Shorr's or Grover's algorithms.

Mitigations:
- Post quantum signature algorithm (ML-DSA or equivalent).
- Random seed keys and rotation for recovery (forward secrecy is resistant as it uses digests).

## Spraying

Using common passphrases to attempt to gain access to accounts.

Mitigations:
- User education. Longer phrases without special characters are just as secure.
- Rate limiting.
- Anti-bot countermeasures.

## Replay

A replay attack occurs when the adversary successfully submits a request that was previously
submitted and receives a response.

Mitigations:
- Authentication: Challenge nonce.
- Rotation: Forward secret key chain.
- Refresh: Forward secret nonce chain.
- Access: Unique nonce + timestamp.

## Spoofing

If the authentication system isn't robust enough, the adversary may simply be able to declare they
are another account.

Mitigations:
- Signing algorithms.

## Forgery

If an attacker can forge a set of valid credentials, they have whatever privileges granted by those
credentials.

Mitigations:
- Signing algorithm choice and strength.

## Hijacking

Stealing a session token to access resources.

Mitigations:
- Access token contains a public key and access requests are signed.

## Side channel

It is sometimes possible to make contextual observations that permit an adversary to obtain more
information about secret cryptographic material.

Mitigations:
- Use of HSMs where possible.
- Use of embedded cryptographic modules on user devices.
- Choice of algorithms.

## Identifier poisoning

If an adversary successfully impersonates an account and it is detected, that account may be banned
from the infrastructure or otherwise restricted. This creates a burden on the true account owner.

Mitigations:
- Random seed keys and rotation for recovery.

## DNS/In the middle

If DNS-based MITM attacks are a concern, consider KERI. There are no protections for the successful
broadcast of malicious server public keys and a middling attack that impersonates and/or proxies
requests to the true backend.

# The Protocols

We now describe registration, authentication, refresh and access protocols.

Registration establishes a public key for use during authentication. Authentication occurs when the
account owner is challenged to provide proof they are an account owner. A refresh token is granted
after successful authentication. The refresh operation is used to obtain a short lived access token.
An access operation uses such an access token to access resources.

These high level descriptions describe the core principles. For implementation details that include
protections and mitigations against various attacks, continue through this document. Key pairs will
be labelled in round brackets following the key (sample).

## Registration

In this process, we bind an account to an authentication key.

1. Through an out of band channel, account identifier is associated with a public key
(authentication). *This step may be unnecessary if operating a decentralized deployment, where
identifiers and keys pre-exist, and ideally are generated and managed entirely by their owners.*

## Authentication

Here, the authentication service challenges the alleged account owner to prove they control the key
used in the registration process to establish a refresh session.

1. Client sends account identifier to auth service.
2. Auth service sends challenge nonce to client.
3. Client constructs signed (authentication) payload consisting of the challenge nonce, a new public
key (refresh), and a pre-commitment digest of a nonce kept secret by the client.
4. Client sends signed payload to authentication service.
5. Authentication service verifies response and associates a new refresh session with the key
supplied in the payload.
6. Authentication service returns an identifier for the refresh session to the client.

## Refresh

During the refresh operation, an account holder is requesting a short-lived access token using a
refresh key established during authentication.

The refresh protocol employs forward secrecy through an evolving nonce chain. Each refresh, the
current nonce is revealed and a next nonce is committed to. A new access key is also established.

1. Client sends refresh session id, current refresh nonce, a pre-commitment digest of the next
refresh nonce and a new public key (access) to authentication service, signed (refresh).
2. Authentication service retrieves the public key (refresh) and current nonce commitment, and
verifies the signature and nonce.
3. Authentication service marks the current nonce as used and commits to the next.
4. Authentication service issues signed access token to the account identifier, inclusive of the
public key (access).
5. Authentication service returns the signed access token to the client.

## Access

When accessing resources, all request bodies are signed (access).

1. Client injects timestamp and random nonce into request body. 
2. Client signs request body (access).
3. Client sends request body, signature, and access token to resource.
4. Resource verifies signature, token, timestamp and uniqueness, and records use of unique nonce.

# Implementation

Implementation details vary depending on what means available one has to generate and store keys.

CESR (primitives for KERI) is used for encoding, as it is cryptographically agile and specifies
tags/codes for common cryptographic material.

## Registration

- Registration must only be performed once per account.
- To associate other keys or modify a passphrase, a current authentication method must be used. An
exception occurs if the account only has one passphrase key defined, in which case a lost or
compromised passphrase will require an out of band transmission for recovery. This is why it is
strongly recommended to establish random seed authentication with rotation as soon as possible in
your user journey.

### Random Seed (preferred)

Random seed authentication relies on entropy generated on a device to establish key pairs.

Random seed authentication with rotation is recoverable because there is already a forward secret
commitment to the next signing key. 

#### Registration material (Auth-OOB->Client)

Auth service delivers registration material out of band.

```json
{
    "payload": {
        "registration": {
            "token": "EOomXwkCWQXvmAHc96c8e1_PF4BGsvWvsMHU6XsP3Zmj"
        },
        "publicKeyDigest": "EPqXgqZ_AiTVBfY2l_-vW016GroHLhLkeYrNc4HQB7WO"
    },
    "signature": "0ICXhZ4M_41TLsp6iMoRyOuWFil9UL7SYY5AcZjx993uNGM1jUXGAxaFg730FJ8sfe0glEPRiTR3ihF2cxjz_61z"
}
```

#### `RegisterAuthenticationKey()` (Client->Auth->Client)

Client generates two assymetic key pairs, preferably in secure hardware where exfiltration of
private material is made exceedingly difficult. One key is labelled `current` and the other `next`.

```json
{
    "payload": {
        "registration": {
            "token": "EOomXwkCWQXvmAHc96c8e1_PF4BGsvWvsMHU6XsP3Zmj"
        },
        "identification": {
            "deviceId": "EAWkUfWVAMzIDy4aHjWwBwaQrmScYMpFobT93Ct6RVv_"
        },
        "authentication": {
            "publicKeys": {
                "current": "1AAIAl-5-nkK7Jp4d1svQnxCEnpuCtwny5Eri4D2n_edfNZf",
                "nextDigest": "ECGWcxYw1bNzyEbuvsnVBnZTTyDDWfwfL_pcyNLawM8O"
            }
        }
    },
    "signature": "0IAIuRf6J9w677nb8NV4OXlXcq9xGFUakaRPLiY4Hmlhmn87GfiNZGO_thFVfzJVRLe6D04DFZj3MdzhTwb463lD"
}
```

The signature above (`current` authentication) is generated on the compact json payload
`authentication.publicKeys.nextDigest` may be ommitted if rotation is not planned (not recommended).

Server responds with the account id that has been assigned.

```json
{
    "payload": {
        "identification": {
            "accountId": "ENBRKI-MIlE-m8h5SY-kLOzmzGhCvovugIvRyXYbrXC3"
        },
        "publicKeyDigest": "EPqXgqZ_AiTVBfY2l_-vW016GroHLhLkeYrNc4HQB7WO"
    },
    "signature": "0ICXhZ4M_41TLsp6iMoRyOuWFil9UL7SYY5AcZjx993uNGM1jUXGAxaFg730FJ8sfe0glEPRiTR3ihF2cxjz_61z"
}
```

*Notes*:
- `registration.token` should be unique.
- `registration.token` should expire after a resonable amount of time, depending on your user
experience requirements. Choose a larger size for the token if your expiration will be far in the
future.
- This example uses a secp256r1 key, which is a good choice here as it is supported by cryptographic
hardware found on common mobile devices.

### Passphrase-based

Passphrase-based authentication relies on keys derived deterministically from passphrases.

#### Registration material (Auth-OOB->Client)

Auth service delivers registration material out of band.

```json
{
    "payload": {
        "registration": {
            "token": "EOomXwkCWQXvmAHc96c8e1_PF4BGsvWvsMHU6XsP3Zmj"
        },
        "passphraseAuthentication": {
            "parameters": "$argon2id$v=19$m=262144,t=3,p=4$",
            "salt": "0AEbin7spiwkRaXks8K5AA9x"
        },
        "publicKeyDigest": "EPqXgqZ_AiTVBfY2l_-vW016GroHLhLkeYrNc4HQB7WO"
    },
    "signature": "0IBKAxkerhXG0hER9Oll5DmyoT-LFkzTST9dfBieHngP7HYtc6fgzYncdaSXLfCM4eTu20QNHmLCqrw7Rb_jzpHX"
}
```

#### `RegisterAuthenticationPassphraseKey()` (Client->Auth->Client)

Client uses Argon2id to derive a key pair (authentication) from a user-supplied passphrase. The
client can choose to ignore derivation parameters and salt if it is managing them itself. This
design permits stateless/multi-device authentication, which is useful for bootstrapping a new
device.

```json
{
    "payload": {
        "registration": {
            "token": "EOomXwkCWQXvmAHc96c8e1_PF4BGsvWvsMHU6XsP3Zmj"
        },
        "passphraseAuthentication": {
            "publicKey": "BOFIM_iwIwrZO3mPxjOqkwTvRfmvNjBQQqrGxk_ncS61"
        }
    },
    "signature": "0BAsKeUTSuvSUJdBsofjGaEmAFtvbaX0YJgyNZS7MCWAkzWA99wIkjgB41FQrcrCd1LgxIULtk7rz2vKDeYkBEIy"
}
```

The signature above is generated with the (authentication) private key.

Server verifies, persists a **digest** of the authentication public key, and responds with the
account id that has been assigned.

```json
{
    "payload": {
        "identification": {
            "accountId": "ENBRKI-MIlE-m8h5SY-kLOzmzGhCvovugIvRyXYbrXC3"
        },
        "publicKeyDigest": "EPqXgqZ_AiTVBfY2l_-vW016GroHLhLkeYrNc4HQB7WO"
    },
    "signature": "0IAsstrWmV_cpbtS0niO7-xUWrR_YtXrqjAQlkhPv4X66qOohd_FfdKC58WggJil1RvTsv9z4F0S-VWkoogzrML7"
}
```

*Notes*:
- `registration.token` should be a unique 256 bit value.
- `registration.token` should expire after a resonable amount of time, depending on your user
experience. One day to one week is a good range.
- This example derives an ed25519 key, which is a good choice for passphrase authentication as it
is easier to support in a browser than some other signature schemes.
- This example uses reasonable derivation parameters for most devices, but one can adjust to suit
one's use case.
- The salt should be an account-wise unique, random, 128 bit value.
- The server persists a digest and not the raw key to further mitigate attacks on the datastore to
reverse passphrases, should the datastore be compromised.

## Rotation

Rotation applies only to random seed keys.

### `RotateAuthenticationKey` (Client->Auth->Client)

The client composes a payload consisting of the newly revealed/current authentication key
(former next, committed to by digest) and a new next key digest. It signs this payload
(`current` authentication - the new one).

```json
{
    "payload": {
        "identification": {
            "accountId": "ENBRKI-MIlE-m8h5SY-kLOzmzGhCvovugIvRyXYbrXC3",
            "deviceId": "EAWkUfWVAMzIDy4aHjWwBwaQrmScYMpFobT93Ct6RVv_"
        },
        "authentication": {
            "publicKeys": {
                "current": "1AAIA7CUSQ_Cvk3XE1ITDNQXS1qpdqEKwCk4q5Q4YP7GtuIq",
                "nextDigest": "EEool9L2Vj-c30J8b0v-yThCVpxIJ5dAXPQSnge3IzvG"
            }
        }
    },
    "signature": "0IAZBlyJEQu-gmS05iYOfUhrDU3NV5Q5E_9PsYF0s5y-QHc5t4j0Rvh-0ljHVcGrt3VL3gB6qodEHDmiZNOhOg2Q"
}
```

Server verifies the signature and stored digest, and updates the next digest and current key, and
returns an acknowledgement.

```json
{
    "payload": {
        "success": true,
        "publicKeyDigest": "EPqXgqZ_AiTVBfY2l_-vW016GroHLhLkeYrNc4HQB7WO"
    },
    "signature": "0IBcQqawkcFHuUgogsnh8tyKqBWnDLY6tbvLVAfw5aE9VxSEx0CQ_A5ILLgnlDX8vrl3X35xi6-p-ytUK5GVLie5"
}
```

## Authentication

### Random Seed (preferred)

#### `BeginAuthentication()` (Client->Auth->Client)

Client identifies account and requests a challenge nonce from auth service.

```json
{
    "identification": {
        "accountId": "ENBRKI-MIlE-m8h5SY-kLOzmzGhCvovugIvRyXYbrXC3"
    }
}
```

Auth generates a random nonce and persists it for verification later, returning the nonce to the
client.

```json
{
    "payload": {
        "authentication": {
            "nonce": "0ADSOF85vtKb4QQTIy319M4j"
        },
        "publicKeyDigest": "EPqXgqZ_AiTVBfY2l_-vW016GroHLhLkeYrNc4HQB7WO"
    },
    "signature": "0IAUi8wD3zLlDzqyG3uB9-jsIpzOXGKqrVSO8UcGpNx8d9E_VZzaM4oovT6Mjqs_edso78MnXpzjTItwdva6zwTZ"
}
```

#### `CompleteAuthentication()` (Client->Auth->Client)

Client creates a payload consisting of a new, random public key (refresh), the challenge nonce, and
the beginning of the evolving refresh nonce chain, a digest of the first nonce. Client returns the
signed (`current` authentication) payload to auth service.

```json
{
    "payload": {
        "identification": {
            "deviceId": "EAWkUfWVAMzIDy4aHjWwBwaQrmScYMpFobT93Ct6RVv_"
        },
        "authentication": {
            "nonce": "0ADSOF85vtKb4QQTIy319M4j"
        },
        "refresh": {
            "publicKey": "1AAIArseHqu34sgRTFelYKd342JUZ1TeJnNMk2xE9NjvtXrD",
            "nonces": {
                "nextDigest": "EC1Hc4KgIsAm7Azif1lxv0HoxhKL_T0UPtQ8ZgeEu1wF"
            }
        }
    },
    "signature": "0IAbiRvVF7Zb7-FVL29VuOE9kR2KezCjCreaYqMjc2okbd7ZPsVTpHbpZVdXeyIjM0KM-f9iykvMyIg3jYkBjobU"
}
```

Auth service verifies signature and nonce and, if correct, stores the key (refresh) and nonce digest
for use during the refresh protocol. It returns a session id to the client.

```json
{
    "payload": {
        "refresh": {
            "sessionId": "EMP0iq5tvNJlIOQoRla5Qa_s7P4X9pzY-50smblRfrw9"
        },
        "publicKeyDigest": "EPqXgqZ_AiTVBfY2l_-vW016GroHLhLkeYrNc4HQB7WO"
    },
    "signature": "0IDLl5gh1G7KYsRK0LAVx4CMqAMeK_q_nUzHnYOxxj7aXidXQPoC1gt5dm3yDvEmqHiFG-keLLmyDwfHEGitl41Q"
}
```

*Notes*:
- `authentication.nonce` should expire soon after creation - as short a time as one minute.
- `authentication.nonce` should have at least as many bits of security as your signing algorithm (128 bits
here).
- `refresh.sessionId` should expire after a reasonable amount of time given the security profile of
the keys used. Twelve hours is a good starting point.
- As mentioned previously, `secp256r1` is likely a better choice than `ed25519` for random seed
authentication.
- `refresh.nonces.nextDigest` provides a commitment to a forward secret that will be revealed as an
evolving chain throughout the refresh session.

### Passphrase-based

#### `BeginPassphraseAuthentication()` (Client->Auth->Client)

Client identifies account and requests a challenge nonce from auth service.

```json
{
    "identification": {
        "accountId": "ENBRKI-MIlE-m8h5SY-kLOzmzGhCvovugIvRyXYbrXC3"
    }
}
```

Auth generates a random nonce and persists it for verification later, returning the nonce to the
client - along with passphrase-based key derivation parameters.

```json
{
    "payload": {
        "passphraseAuthentication": {
            "nonce": "0ADSOF85vtKb4QQTIy319M4j",
            "parameters": "$argon2id$v=19$m=262144,t=3,p=4$",
            "salt": "0AEbin7spiwkRaXks8K5AA9x"
        },
        "publicKeyDigest": "EPqXgqZ_AiTVBfY2l_-vW016GroHLhLkeYrNc4HQB7WO"
    },
    "signature": "0IDk7TGXAnU_6aqhZPO7yOROlDLhwzElJXvm2d0qJS-qFCRdwDnstxy6ttJyogxKz4IQxUaZaweQc9wvHbbWdJWG"
}
```

#### `CompletePassphraseAuthentication()` (Client->Auth->Client)

Client creates a payload consisting of a new, random public key (refresh) and the challenge nonce.
Client returns the signed (`current` authentication) payload to auth service.

```json
{
    "payload": {
        "passphraseAuthentication": {
            "nonce": "0ADSOF85vtKb4QQTIy319M4j",
            "publicKey": "BOFIM_iwIwrZO3mPxjOqkwTvRfmvNjBQQqrGxk_ncS61"
        },
        "refresh": {
            "publicKey": "1AAIArseHqu34sgRTFelYKd342JUZ1TeJnNMk2xE9NjvtXrD",
            "nonces": {
                "nextDigest": "EC1Hc4KgIsAm7Azif1lxv0HoxhKL_T0UPtQ8ZgeEu1wF"
            }
        }
    },
    "signature": "0BD1WQsuqNXG4wBTalLpwLYxdz3xgtjF05aBcg3ZoFzaDsfqPpobEE2s9fJjHIRMAhhGCpCRsfpC4i1jjNdkrROK"
}
```

Auth service verifies signature and nonce and, if correct, compares the public key (authentication)
digest to that which it stored during registration. If that matches, auth stores the key (refresh)
for use during the refresh protocol, binding it to that session. It returns a session id to the
client.

```json
{
    "payload": {
        "refresh": {
            "sessionId": "EMP0iq5tvNJlIOQoRla5Qa_s7P4X9pzY-50smblRfrw9"
        },
        "publicKeyDigest": "EPqXgqZ_AiTVBfY2l_-vW016GroHLhLkeYrNc4HQB7WO"
    },
    "signature": "0IBnIffOKisy1nd63tMdupzmpcpRQJjER7plDCgcxPrRPPjggi6JDIRIB7zzFg--rlNBqdBg0dcBtQtFhRwcaMxD"
}
```

*Notes*:
- `passphraseAuthentication.nonce` should expire soon after creation - as short a time as one minute.
- `refresh.sessionId` should expire after a reasonable amount of time given the security profile of
the keys used. Twelve hours is a good starting point.
- `passphraseAuthentication.publicKey` is supplied, since only the digest of the key is stored.
- `refresh.nonces.nextDigest` provides a commitment to a forward secret that will be revealed as an
evolving chain throughout the refresh session.

## Refresh

The refresh operation is used to acquire a short-lived access token.

### `RefreshAccessToken()` (Client->Auth->Client)

Client constructs refresh payload consisting of a new random public key (access) to be used for
access to resources, the session id, the newly revealed current nonce and a commitment to the next.
This payload is signed (refresh).

```json
{
    "payload": {
        "refresh": {
            "sessionId": "EMP0iq5tvNJlIOQoRla5Qa_s7P4X9pzY-50smblRfrw9",
            "nonces": {
                "current": "0AhfUcHYwHdfn69sF9HqdGg-",
                "nextDigest": "EJ6cZ-LKxUNyuS6mZKyydY6JOBhpHaFnf34AYtudnMRV",
            }
        },
        "access": {
            "publicKey": "1AAIA7UjnxSVGI1gabpe9W6fU7yK7VUL5u3TFu7nI2D03DPH"
        }
    },
    "signature": "0IB8dO5R5L5Y27HQGtzxhi1SyXX_mjRR-SLP35KkzywiMygFOHDJf27DMh8O1UOIwpGwHWqhejE-wGj1oE7JHPAQ"
}
```

Auth service verifies signature and current nonce and stores next digest. It constructs an access
token and returns it to the client. Attributes in the token can provide further granularity over
resource access

```json
{
    "payload": {
        "access": {
            "token": {
                "identification": {
                    "accountId": "ENBRKI-MIlE-m8h5SY-kLOzmzGhCvovugIvRyXYbrXC3"
                },
                "publicKey": "1AAIA7UjnxSVGI1gabpe9W6fU7yK7VUL5u3TFu7nI2D03DPH",
                "issuedAt": "2025-09-15T09:10:00Z",
                "expiry": "2025-09-15T09:25:00Z",
                "attributes": {
                    "label": "value"
                }
            },
            "signature": "0ICqCbTD10ciOuNZGzjxySGs46xhJF39MLGHx09UEFljxvArv7YoDss3OhUYj7T4l0oR9yElrk0eSlqSiXwG6KZ7"
        },
        "publicKeyDigest": "EPqXgqZ_AiTVBfY2l_-vW016GroHLhLkeYrNc4HQB7WO"
    },
    "signature": "0ICRa_DmuiriwY3e-_rURIgLVrXbytXNS7wzh4aLT-ViouI4OLAhBglwnifxJCR0KMqIDj53suTomaa8OszhtBtM"
}
```

*Notes*:
- The inner signature here is for internal use by the backend, to verify auth created the token,
during access. Management of backend keys is up to the implementer. The outer signature is the
typical server identifying signature.

#### Token Encoding

A convenient way to package this is to prepend the signature to a gzipped, url-safe and unpadded
base64 encoding of the accessToken.

```shell
echo '{
            "identification": {
                "accountId": "ENBRKI-MIlE-m8h5SY-kLOzmzGhCvovugIvRyXYbrXC3"
            },
            "publicKey": "1AAIA7UjnxSVGI1gabpe9W6fU7yK7VUL5u3TFu7nI2D03DPH",
            "issuedAt": "2025-09-15T09:10:00Z",
            "expiry": "2025-09-15T09:25:00Z",
            "attributes": {
                "label": "value"
            }
        }' | jq -c -M | gzip | base64 | tr '+' '-' | tr '/' '_'
```

produces:

```
H4sIAMHLyGgAA2WPQW-CMBhA7_sZ39kmBVIZ3BCdNjhdVJzu1kLVai0EWiIa_ruYeNv5vXd4D5C50EYeZMaMLDSED2BZVlhtaA4hTBajVULRN1UTdP08kfUeXebL-_U-PcVN0dgjbVbtbs-rXexBN4DSciWzRLR960QRjfz0rG_r7ZQ6R8ZLEfwOD6nfJv42nRPrbb6sr6k7xt74ZwYDkHVtRR6ZvnaxSxAOkEM2OAgdHGL81xviVsqq_cdd8ubMmEpya0T9WlGMC9XLDVNWQNd9PAE1tAWU8AAAAA
```

Prepending the signature, we get:

```
0ICqCbTD10ciOuNZGzjxySGs46xhJF39MLGHx09UEFljxvArv7YoDss3OhUYj7T4l0oR9yElrk0eSlqSiXwG6KZ7H4sIAMHLyGgAA2WPQW-CMBhA7_sZ39kmBVIZ3BCdNjhdVJzu1kLVai0EWiIa_ruYeNv5vXd4D5C50EYeZMaMLDSED2BZVlhtaA4hTBajVULRN1UTdP08kfUeXebL-_U-PcVN0dgjbVbtbs-rXexBN4DSciWzRLR960QRjfz0rG_r7ZQ6R8ZLEfwOD6nfJv42nRPrbb6sr6k7xt74ZwYDkHVtRR6ZvnaxSxAOkEM2OAgdHGL81xviVsqq_cdd8ubMmEpya0T9WlGMC9XLDVNWQNd9PAE1tAWU8AAAAA
```

## Access

To access resources, a message is constructed with a payload and signature. The payload contains
the request body, a timestamp and a unique nonce. The payload is signed (access) to produce the
signature.

(Client->Resource)

```json
{
    "token": "0ICqCbTD10ciOuNZGzjxySGs46xhJF39MLGHx09UEFljxvArv7YoDss3OhUYj7T4l0oR9yElrk0eSlqSiXwG6KZ7H4sIAMHLyGgAA2WPQW-CMBhA7_sZ39kmBVIZ3BCdNjhdVJzu1kLVai0EWiIa_ruYeNv5vXd4D5C50EYeZMaMLDSED2BZVlhtaA4hTBajVULRN1UTdP08kfUeXebL-_U-PcVN0dgjbVbtbs-rXexBN4DSciWzRLR960QRjfz0rG_r7ZQ6R8ZLEfwOD6nfJv42nRPrbb6sr6k7xt74ZwYDkHVtRR6ZvnaxSxAOkEM2OAgdHGL81xviVsqq_cdd8ubMmEpya0T9WlGMC9XLDVNWQNd9PAE1tAWU8AAAAA",
    "payload": {
        "access": {
            "timestamp": "2025-09-15T09:13:22Z",
            "nonce": "0APUZ10BG425SyJMGEvNzZcl"
        },
        "request": {
            "foo": "bar"
        }
    },
    "signature": "0IDRXueppRC38Nkd7i1mMpXBUvvX6aLHHVWST6gynlQEqwZ316e5JOpWbWwbk3FYxteDHErlJOYWaxa1L9AHoby8"
}
```

When a resource (or proxy) receives such a request and unpacks the token, it first verifies the
signature on the access token. Then it verifies the temporal validity of the token using `issuedAt`
and `expiry` (refer to the previous section for token format). It then uses the accessPublicKey to
verify the top level `signature`. It next checks `timestamp` to ensure the request is recent (30
seconds or less is recommended) and verifies the nonce hasn't been used recently (same time scale),
storing the nonce for future checks. At this point application level checks are made to ensure the
resource is permitted to be accessed using attributes in the token. If all the preceding checks
pass, access is granted.
