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
location. `responseKeyDigest` serves as a lookup key.

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

#### Creation container (Auth-OOB->Client)

Auth service delivers registration material out of band.

```json
{
  "payload": {
    "access": {
      "responseKeyDigest": "EKMVkRIDGAeqrWaPWq74PTRcEUfjWfjo2kwLawSfAMjF",
      "nonce": "0AAOkha7B8VlRMt2aqvLGl9B"
    },
    "response": {
      "registration": {
        "token": "EBkilHXVOQ0zmYYqKN_6oRi0OmWBXnUdfG0UMDWc0UAf"
      }
    }
  },
  "signature": "0IC3124neVw0c0e6hSe136tiGXJmC3O9mUqWpg_VTl4SULA2RWKgTPxmLURMC7yeRZqMqxeWfhtdChQaTUeZrP_Y"
}
```

#### `CreateAccount()` (Client->Auth->Client)

Client generates two assymetic key pairs, preferably in secure hardware where exfiltration of
private material is made exceedingly difficult. One key is labelled `current` and the other `next`.

```json
{
  "payload": {
    "registration": {
      "token": "EBkilHXVOQ0zmYYqKN_6oRi0OmWBXnUdfG0UMDWc0UAf"
    },
    "identification": {
      "deviceId": "EAIyck1GCdreB_25IhJVloWHs_ov9DDqclCjanugNW5-"
    },
    "authentication": {
      "publicKeys": {
        "current": "1AAIAjlxLtdaoTNHwSZof7eLp64xsguAHzAoXaAIIqa6rjp9",
        "nextDigest": "EHM0ZhBfFL1QqxnsgD6tLOdB5s2g1jLD0qucP1IhHVTJ"
      }
    }
  },
  "signature": "0IA_65kbtjUsjFCe7hFbGyLi4SvaXvDx5SXxqEd8jQuq6-dv3p4XildQ6u9b0ecZiUfRXZyqnjXL5RPWApPmYZ33"
}
```

The signature above (`current` authentication) is generated on the compact json payload.

Server responds with the account id that has been assigned.

```json
{
  "payload": {
    "access": {
      "responseKeyDigest": "EKMVkRIDGAeqrWaPWq74PTRcEUfjWfjo2kwLawSfAMjF",
      "nonce": "0AA3RJRs3SqWuLnL0VejsudK"
    },
    "response": {
      "identification": {
        "accountId": "EBJ7ATsAVObGQ9m5IIpPiQNgAbESN_JC1WUErNsU66tA"
      }
    }
  },
  "signature": "0ICkPi_2h4KG-JzWOfUiN3MnwtwMY5Qb_AjcgXKcgOBAn9HBpwFCfpv5AqWDUBZjr9aLMyRwc6_JErV-OjX9m3W7"
}
```

*Notes*:
- `registration.token` should be unique.
- `registration.token` should expire after a resonable amount of time, depending on your user
experience requirements. Choose a larger size for the token if your expiration will be far in the
future.

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
      "accountId": "EBJ7ATsAVObGQ9m5IIpPiQNgAbESN_JC1WUErNsU66tA",
      "deviceId": "EAIyck1GCdreB_25IhJVloWHs_ov9DDqclCjanugNW5-"
    },
    "authentication": {
      "publicKeys": {
        "current": "1AAIA51XIkJiZIUhqXkK_aPZckKIolykA0tnIiiBmz4DN1CZ",
        "nextDigest": "EG3izUx0KwpbRPeAgQP2NQ_qwZVQpA8F_KoccQgSYqIN"
      }
    }
  },
  "signature": "0IBnehTenLbownl_6hRwuHc9j3yoy9mXENvyh1okdxo1aIwFFJulE9oZjMTJRUuwlsbwCdDyMPOHqQl0eWE98h2o"
}
```

Server verifies the signature and stored digest, and updates the next digest and current key, and
returns an acknowledgement.

```json
{
  "payload": {
    "access": {
      "responseKeyDigest": "EKMVkRIDGAeqrWaPWq74PTRcEUfjWfjo2kwLawSfAMjF",
      "nonce": "0AAW9n_-dR43-3rrL3seymq2"
    },
    "response": {}
  },
  "signature": "0ICqOpjTmUmIAfpuleFGD-WBX_dgD3tx6JLzH56x5O5VVOiyeOHZdiKTCZFGQRSEy42RvsTc1NzY1-3jwEy3gG6x"
}
```

## Authentication

### Random Seed (preferred)

#### `BeginAuthentication()` (Client->Auth->Client)

Client identifies account and requests a challenge nonce from auth service.

```json
{
  "payload": {
    "identification": {
      "accountId": "EBJ7ATsAVObGQ9m5IIpPiQNgAbESN_JC1WUErNsU66tA"
    }
  }
}
```

Auth generates a random nonce and persists it for verification later, returning the nonce to the
client.

```json
{
  "payload": {
    "access": {
      "responseKeyDigest": "EKMVkRIDGAeqrWaPWq74PTRcEUfjWfjo2kwLawSfAMjF",
      "nonce": "0ACRqsjH4S7sdXVGbefedRKH"
    },
    "response": {
      "authentication": {
        "nonce": "0AB7XWhxRM5GguoIRCRWeFme"
      }
    }
  },
  "signature": "0IAV8eGsdLV3dWfZ6Hu6GVylxxPwx1gbceXqLraWXXQdtLsIe0CO8Mfs2OMrv-O_krybRGKZh23MWFkbrgI41Q-v"
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
      "deviceId": "EAIyck1GCdreB_25IhJVloWHs_ov9DDqclCjanugNW5-"
    },
    "authentication": {
      "nonce": "0AB7XWhxRM5GguoIRCRWeFme"
    },
    "access": {
      "publicKeys": {
        "current": "1AAIA-K8gdmEHhsx1bl0vVfp_eDPG06ax_-nkjokfnAowJNk",
        "nextDigest": "EDSnwtLkPpNFugLD4w7aTPCjqxThr28o3-XOm847yZl7"
      }
    }
  },
  "signature": "0IBVL0g3HTOp4Jj1lY-WAjFNpqa9eenzRrzPAXtIzqwKpcaNT4E3ViMXyYmkk6LTEdaYtT1i3ouv_qMzJxTH9Dmx"
}
```

Auth service verifies signature and nonce and, if correct, stores the key (refresh) and nonce digest
for use during the refresh protocol. It returns a session id to the client.

```json
{
  "payload": {
    "access": {
      "responseKeyDigest": "EKMVkRIDGAeqrWaPWq74PTRcEUfjWfjo2kwLawSfAMjF",
      "nonce": "0ABsoh19OkxRGNg-XUTcrGvn"
    },
    "response": {
      "access": {
        "token": "0ID-GmoX9a5O33LnDrZf2RzT53vf4UlRHmqzqII0fWdKcp1rePGiyslGCI0cBINLEF8yOIWE8RmN_1qWvC2381WCH4sIAAAAAAACA23O0W6CMBQG4Hfp9VhKQVHuqjCHGsSJbnFZCEjFChTWlgExvPvqbt25PPm__5wbiE-nqmHSS4EN3NnSwqHAh02y2E7LkefVAd36GU7cnR8t5_r73uW-2I_HEoMnUDdJQU8r0iuqY-xhbTXJ0tJ9vYhOTwr4czjXEXGCBRzHXaSx_FrlZ4ardunnijPSSYdmRMj7aWfHWrnOg9p_abK1Y7ZWHAbz63cXXjiaVIb2sSknptUfC0tZKkRDUnyXCKKRBqcaQqFu2nBqI_15ZFjwb44qS7qa8v4hicyHJCdnTsTFfQBGCNF_1bGUnCaNJALYN1ATXqrHaMXErH-rCnJfxmlJGbA_VXmcKtJyKgn4GobhF9_IpQp8AQAA"
      }
    }
  },
  "signature": "0IBnttfERYPXHENGEl0Itvr89rbZ-15UPoiV7h1KWgEv4_28Y0Fe3rG6MCYYkwzrxUiTKxTj9aGjcVgnywr7pveB"
}
```

*Notes*:
- `authentication.nonce` should expire soon after creation - as short a time as one minute.
- `authentication.nonce` should have at least as many bits of security as your signing algorithm (128 bits
here).
- `refresh.sessionId` should expire after a reasonable amount of time given the security profile of
the keys used. Twelve hours is a good starting point.
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
    "access": {
      "token": "0ID-GmoX9a5O33LnDrZf2RzT53vf4UlRHmqzqII0fWdKcp1rePGiyslGCI0cBINLEF8yOIWE8RmN_1qWvC2381WCH4sIAAAAAAACA23O0W6CMBQG4Hfp9VhKQVHuqjCHGsSJbnFZCEjFChTWlgExvPvqbt25PPm__5wbiE-nqmHSS4EN3NnSwqHAh02y2E7LkefVAd36GU7cnR8t5_r73uW-2I_HEoMnUDdJQU8r0iuqY-xhbTXJ0tJ9vYhOTwr4czjXEXGCBRzHXaSx_FrlZ4ardunnijPSSYdmRMj7aWfHWrnOg9p_abK1Y7ZWHAbz63cXXjiaVIb2sSknptUfC0tZKkRDUnyXCKKRBqcaQqFu2nBqI_15ZFjwb44qS7qa8v4hicyHJCdnTsTFfQBGCNF_1bGUnCaNJALYN1ATXqrHaMXErH-rCnJfxmlJGbA_VXmcKtJyKgn4GobhF9_IpQp8AQAA",
      "publicKeys": {
        "current": "1AAIA2IO919-lnyF-lYSkhw76irIQ7D_ZFwLAVzkWMIv90Nd",
        "nextDigest": "EA-17Qz3InFohMXpu5egG2ZNK9U1bknMVWoJobXMnqhg"
      }
    }
  },
  "signature": "0ICG5B3-EZjBmzs5NeP8_YMgT6pIDe4Fm-wnPVQq4VJ8KHn-C4suhwyoY-YIAE728ld5ZUC-cAXOwX4GeG7pADwb"
}
```

Auth service verifies signature and current nonce and stores next digest. It constructs an access
token and returns it to the client. Attributes in the token can provide further granularity over
resource access

```json
{
  "payload": {
    "access": {
      "responseKeyDigest": "EKMVkRIDGAeqrWaPWq74PTRcEUfjWfjo2kwLawSfAMjF",
      "nonce": "0AC3igP_bzlacowas1QcrDm2"
    },
    "response": {
      "access": {
        "token": "0IBFd_Wo_Td26csEWisAP1pZxEKLRZOaQVGr_VXJG4cpAH-KBMqyiVBb7MLexte9IROQPfi0d2JCWpsKRWjvH39PH4sIAAAAAAACA2WPXW-CMBSG_0uvx0ILSMpdnWiqA8f8HMtiQDpoxMLaMkXjfx8sWXbhuTx5nvec9wqS_b5qhKYZ8IA_nLpkqch6nk4ifHQorV94FOYk9RfhbvoENytfhmo1GGgCHkDdpCXfz1jbqZAQShCdY4iNUrRjo3xbHIqTO-CSRu5oF49Pz2R9OWwC-o3NMOt0wc56xHOmdH-aGNCNLhYV46oItnXjsHyC4nCGVzA9iGC9qaZVug3EV5F3LleqYRnpTWQixzCxgdAS2p6JPQQfHdsyfyfuWHauuWzvSGTfkZJ9SqYK_06wlib6i7bcfyHRWvK00UwB7wpqJo_dY7wSati-ViXrl0l25AJ471140rc-Sa4Z-Ljdbj8_ocnsfAEAAA"
      }
    }
  },
  "signature": "0IC_UDHYYEf31exfUl945ZgDjmCBsAdDX-ChMU6WBL9wyEHGDq2V88bS7B5XU4Y2sN7TTWHUB6_NzVNuos_y25o2"
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
echo '{"accountId":"EBJ7ATsAVObGQ9m5IIpPiQNgAbESN_JC1WUErNsU66tA","publicKey":"1AAIA2IO919-lnyF-lYSkhw76irIQ7D_ZFwLAVzkWMIv90Nd","nextDigest":"EA-17Qz3InFohMXpu5egG2ZNK9U1bknMVWoJobXMnqhg","issuedAt":"2025-09-22T14:09:21.543000000Z","expiry":"2025-09-22T14:24:21.543000000Z","refreshExpiry":"2025-09-23T02:09:21.537000000Z","attributes":{"permissionsByRole":{"admin":["read","write"]}}}' | jq -c -M | gzip -9 | base64 | tr '+' '-' | tr '/' '_' | tr -d '='
```

produces something like:

```
H4sIAAAAAAACA2WPXW-CMBSG_0uvx0ILSMpdnWiqA8f8HMtiQDpoxMLaMkXjfx8sWXbhuTx5nvec9wqS_b5qhKYZ8IA_nLpkqch6nk4ifHQorV94FOYk9RfhbvoENytfhmo1GGgCHkDdpCXfz1jbqZAQShCdY4iNUrRjo3xbHIqTO-CSRu5oF49Pz2R9OWwC-o3NMOt0wc56xHOmdH-aGNCNLhYV46oItnXjsHyC4nCGVzA9iGC9qaZVug3EV5F3LleqYRnpTWQixzCxgdAS2p6JPQQfHdsyfyfuWHauuWzvSGTfkZJ9SqYK_06wlib6i7bcfyHRWvK00UwB7wpqJo_dY7wSati-ViXrl0l25AJ471140rc-Sa4Z-Ljdbj8_ocnsfAEAAA
```

Prepending the signature, we get:

```
0IBFd_Wo_Td26csEWisAP1pZxEKLRZOaQVGr_VXJG4cpAH-KBMqyiVBb7MLexte9IROQPfi0d2JCWpsKRWjvH39PH4sIAAAAAAACA2WPXW-CMBSG_0uvx0ILSMpdnWiqA8f8HMtiQDpoxMLaMkXjfx8sWXbhuTx5nvec9wqS_b5qhKYZ8IA_nLpkqch6nk4ifHQorV94FOYk9RfhbvoENytfhmo1GGgCHkDdpCXfz1jbqZAQShCdY4iNUrRjo3xbHIqTO-CSRu5oF49Pz2R9OWwC-o3NMOt0wc56xHOmdH-aGNCNLhYV46oItnXjsHyC4nCGVzA9iGC9qaZVug3EV5F3LleqYRnpTWQixzCxgdAS2p6JPQQfHdsyfyfuWHauuWzvSGTfkZJ9SqYK_06wlib6i7bcfyHRWvK00UwB7wpqJo_dY7wSati-ViXrl0l25AJ471140rc-Sa4Z-Ljdbj8_ocnsfAEAAA
```

## Access

To access resources, a message is constructed with a payload and signature. The payload contains
the request body, a timestamp and a unique nonce. The payload is signed (access) to produce the
signature.

(Client->Resource)

```json
{
  "payload": {
    "token": "0IBFd_Wo_Td26csEWisAP1pZxEKLRZOaQVGr_VXJG4cpAH-KBMqyiVBb7MLexte9IROQPfi0d2JCWpsKRWjvH39PH4sIAAAAAAACA2WPXW-CMBSG_0uvx0ILSMpdnWiqA8f8HMtiQDpoxMLaMkXjfx8sWXbhuTx5nvec9wqS_b5qhKYZ8IA_nLpkqch6nk4ifHQorV94FOYk9RfhbvoENytfhmo1GGgCHkDdpCXfz1jbqZAQShCdY4iNUrRjo3xbHIqTO-CSRu5oF49Pz2R9OWwC-o3NMOt0wc56xHOmdH-aGNCNLhYV46oItnXjsHyC4nCGVzA9iGC9qaZVug3EV5F3LleqYRnpTWQixzCxgdAS2p6JPQQfHdsyfyfuWHauuWzvSGTfkZJ9SqYK_06wlib6i7bcfyHRWvK00UwB7wpqJo_dY7wSati-ViXrl0l25AJ471140rc-Sa4Z-Ljdbj8_ocnsfAEAAA",
    "access": {
      "timestamp": "2025-09-22T14:09:21.544000000Z",
      "nonce": "0ADopcW54nmDODrOs1FDqMBY"
    },
    "request": {
      "foo": "foo-y",
      "bar": "bar-y"
    }
  },
  "signature": "0IDLtryo3YWJlupBUtPSjHKGNHpzLt1uS3sX8u8-i-fqr4OSZFZlqpPNeSVoiHXnpUe2sNq9Cq9a8vgZTQLjwifp"
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

Here is a response, inclusive of the challence nonce in the request.

```json
{
  "payload": {
    "access": {
      "responseKeyDigest": "1AAIAqYzzZkbO8y-qWeYvn_UHyEPKLo9AsVWudjhYh17hEmA",
      "nonce": "0ADopcW54nmDODrOs1FDqMBY"
    },
    "response": {
      "wasFoo": "foo-y",
      "wasBar": "bar-y"
    }
  },
  "signature": "0ICjXUFRyT2l8KT3lYZuWHhq5m2lLt-CMantMbPnon2mDuH_8izuBAqRIIBaiXRBNCZyWJJZufV-4GfI31YiEOfe"
}
```