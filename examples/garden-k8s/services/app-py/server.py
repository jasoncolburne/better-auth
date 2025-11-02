#!/usr/bin/env python3
"""Python application server for Better Auth examples.

This server demonstrates how to use the BetterAuth Python implementation
to verify authenticated access requests.
"""

import asyncio
import base64
import json
import logging
import os
import signal
import sys
import threading
from concurrent.futures import Future
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional

import httpx
import redis.asyncio as aioredis
from flask import Flask, request, Response

# Add the better-auth-py implementation to the path
# In Docker: /dependencies/better-auth-py
# In local dev: ../../../../implementations/better-auth-py (relative to this file)
if os.path.exists('/dependencies/better-auth-py'):
    better_auth_path = '/dependencies/better-auth-py'
    examples_path = '/dependencies/better-auth-py/examples'
else:
    better_auth_path = os.path.join(os.path.dirname(__file__), '../../../../implementations/better-auth-py')
    examples_path = os.path.join(os.path.dirname(__file__), '../../../../implementations/better-auth-py/examples')

sys.path.insert(0, better_auth_path)

from better_auth.api import AccessVerifier, AccessVerifierConfig, AccessVerifierCryptoConfig, AccessVerifierEncodingConfig, AccessVerifierStorageConfig, AccessVerifierStoreConfig
from better_auth.messages import ServerResponse
from better_auth.interfaces.crypto import ISigningKey, IVerificationKey, IVerifier
from better_auth.interfaces.storage import IServerTimeLockStore, IVerificationKeyStore

# Import reference implementations
sys.path.insert(0, examples_path)
from implementation.crypto.secp256r1 import Secp256r1, Secp256r1Verifier
from implementation.encoding.timestamper import Rfc3339
from implementation.encoding.token_encoder import TokenEncoder
from key_verifier import KeyVerifier
from utils import get_sub_json

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s: %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)


class VerificationKey(IVerificationKey):
    """Wrapper for a public key string that implements IVerificationKey."""

    def __init__(self, public_key: str, verifier_instance: IVerifier):
        self._public_key = public_key
        self._verifier = verifier_instance

    async def public(self) -> str:
        """Return the public key."""
        return self._public_key

    def verifier(self) -> IVerifier:
        """Return the verifier instance."""
        return self._verifier

    async def verify(self, message: str, signature: str) -> None:
        """Verify a signature using the verifier and public key."""
        await self._verifier.verify(message, signature, self._public_key)


class RedisVerificationKeyStore(IVerificationKeyStore):
    """Redis-backed verification key store with HSM key verification."""

    def __init__(self, redis_client: aioredis.Redis, redis_host: str, redis_db_hsm_keys: int, server_lifetime_hours: int, access_lifetime_minutes: int):
        self.redis_client = redis_client
        self.key_verifier = KeyVerifier(redis_host, redis_db_hsm_keys, server_lifetime_hours, access_lifetime_minutes)
        self.verifier = Secp256r1Verifier()

    async def get(self, identity: str) -> IVerificationKey:
        """Get a verification key from Redis."""
        value = await self.redis_client.get(identity)
        if value is None:
            raise ValueError(f"Key not found for identity: {identity}")

        # Decode bytes to string if necessary
        if isinstance(value, bytes):
            value = value.decode('utf-8')

        # Parse the response structure
        response_obj = json.loads(value)
        body_json = get_sub_json(value, "body")

        # Verify HSM signature using KeyVerifier
        await self.key_verifier.verify(
            response_obj['signature'],
            response_obj['body']['hsm']['identity'],
            response_obj['body']['hsm']['generationId'],
            body_json
        )

        # Validate purpose
        payload = response_obj['body']['payload']
        if payload.get('purpose') != 'access':
            raise ValueError(f"invalid purpose: expected access, got {payload.get('purpose')}")

        # Check expiration
        expiration_str = payload.get('expiration')
        if expiration_str:
            expiration = datetime.fromisoformat(expiration_str.replace('Z', '+00:00'))
            if expiration <= datetime.now(expiration.tzinfo):
                raise ValueError("key expired")

        # Return the public key from the payload
        public_key = payload.get('publicKey')
        if not public_key:
            raise ValueError("missing publicKey in payload")

        return VerificationKey(public_key, self.verifier)

    async def close(self) -> None:
        """Close KeyVerifier connection."""
        await self.key_verifier.close()


class InMemoryTimeLockStore(IServerTimeLockStore):
    """In-memory time-lock store for nonces with configurable window."""

    def __init__(self, lifetime_in_seconds: int):
        self._lifetime_in_seconds = lifetime_in_seconds
        self._nonces: Dict[str, datetime] = {}

    @property
    def lifetime_in_seconds(self) -> int:
        return self._lifetime_in_seconds

    async def reserve(self, value: str) -> None:
        """Reserve a value in the time-lock store."""
        from datetime import timedelta

        valid_at = self._nonces.get(value)
        now = datetime.now()

        if valid_at is not None and now < valid_at:
            raise RuntimeError("value reserved too recently")

        new_valid_at = now + timedelta(seconds=self._lifetime_in_seconds)
        self._nonces[value] = new_valid_at


class ApplicationServer:
    """Application server that handles authenticated requests."""

    def __init__(self):
        self.verifier: Optional[AccessVerifier] = None
        self.response_key: Optional[ISigningKey] = None
        self.access_client: Optional[aioredis.Redis] = None
        self.revoked_devices_client: Optional[aioredis.Redis] = None

    async def initialize(self) -> None:
        """Initialize the application server."""
        redis_host = os.environ.get('REDIS_HOST', 'redis:6379')
        logger.info(f"Connecting to Redis at {redis_host}")

        server_lifetime_hours = 12
        access_lifetime_minutes = 15

        redis_db_access_keys = int(os.environ.get('REDIS_DB_ACCESS_KEYS', '0'))
        redis_db_response_keys = int(os.environ.get('REDIS_DB_RESPONSE_KEYS', '1'))
        redis_db_revoked_devices = int(os.environ.get('REDIS_DB_REVOKED_DEVICES', '3'))
        redis_db_hsm_keys = int(os.environ.get('REDIS_DB_HSM_KEYS', '4'))

        # Parse Redis host and port
        if ':' in redis_host:
            host, port = redis_host.split(':')
            port = int(port)
        else:
            host = redis_host
            port = 6379

        # Connect to Redis DB 0 to read access keys
        self.access_client = aioredis.Redis(
            host=host,
            port=port,
            db=redis_db_access_keys,
            decode_responses=False  # We'll handle decoding ourselves
        )

        # Connect to Redis DB 3 to check revoked devices
        self.revoked_devices_client = aioredis.Redis(
            host=host,
            port=port,
            db=redis_db_revoked_devices,
            decode_responses=False
        )

        # Connect to Redis DB 1 to write/read response keys
        response_client = aioredis.Redis(
            host=host,
            port=port,
            db=redis_db_response_keys,
            decode_responses=False
        )

        try:
            # Create verification key store
            verifier = Secp256r1Verifier()
            verification_key_store = RedisVerificationKeyStore(
                self.access_client, redis_host, redis_db_hsm_keys, server_lifetime_hours, access_lifetime_minutes
            )

            # Create an in-memory nonce store with 30 second window
            access_nonce_store = InMemoryTimeLockStore(30)

            # Create AccessVerifier
            self.verifier = AccessVerifier(
                AccessVerifierConfig(
                    crypto=AccessVerifierCryptoConfig(
                        access_key_store=verification_key_store,
                        verifier=verifier
                    ),
                    encoding=AccessVerifierEncodingConfig(
                        token_encoder=TokenEncoder(),
                        timestamper=Rfc3339()
                    ),
                    store=AccessVerifierStorageConfig(
                        access=AccessVerifierStoreConfig(
                            nonce=access_nonce_store
                        )
                    )
                )
            )

            logger.info("AccessVerifier initialized")

            # Generate app response key
            app_response_key = Secp256r1()
            await app_response_key.generate()
            app_response_public_key = await app_response_key.public()

            # Sign response key with HSM
            hsm_host = os.environ.get('HSM_HOST', 'hsm')
            hsm_port = os.environ.get('HSM_PORT', '11111')
            hsm_url = f"http://{hsm_host}:{hsm_port}"

            ttl = 12 * 60 * 60 + 60  # 12 hours + 1 minute in seconds
            timestamper = Rfc3339()
            response_expiration = timestamper.format(datetime.now(timezone.utc) + timedelta(seconds=ttl))
            response_payload = {
                "purpose": "response",
                "publicKey": app_response_public_key,
                "expiration": response_expiration
            }

            authorization = None
            try:
                async with httpx.AsyncClient() as client:
                    sign_response = await client.post(
                        f"{hsm_url}/sign",
                        json={"payload": response_payload}
                    )
                    if sign_response.status_code == 200:
                        authorization = sign_response.text.rstrip()
                        logger.info(f"Response key HSM authorization: {authorization}")
                    else:
                        logger.warning(f"Failed to sign response key with HSM: {sign_response.status_code}")
            except Exception as e:
                logger.warning(f"Failed to contact HSM: {e}")

            # Store the full HSM authorization in Redis DB 1 with 12 hour 1 minute TTL
            if authorization:
                await response_client.set(app_response_public_key, authorization, ex=ttl)
                logger.info(f"Registered app response key in Redis DB 1 (TTL: 12 hours): {app_response_public_key[:20]}...")
            else:
                logger.error("No HSM authorization to store in Redis")

            self.response_key = app_response_key
        except:
            raise
        finally:
            await response_client.aclose()

        logger.info("Application server initialized")

    async def cleanup(self) -> None:
        """Clean up resources."""
        if self.access_client:
            await self.access_client.aclose()
        if self.revoked_devices_client:
            await self.revoked_devices_client.aclose()


# Global server instance
server_instance = ApplicationServer()

# Event loop runner for async operations
_loop = None
_loop_thread = None


def _run_event_loop(loop):
    """Run the event loop in a dedicated thread."""
    asyncio.set_event_loop(loop)
    loop.run_forever()


def run_async(coro):
    """Run an async coroutine in the background event loop."""
    if _loop is None:
        raise RuntimeError("Event loop not initialized")

    future = asyncio.run_coroutine_threadsafe(coro, _loop)
    return future.result()


@app.before_request
def handle_cors_preflight():
    """Handle CORS preflight requests."""
    if request.method == 'OPTIONS':
        response = Response()
        response.headers['Access-Control-Allow-Origin'] = '*'
        response.headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
        response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization'
        return response


@app.after_request
def add_cors_headers(response):
    """Add CORS headers to all responses."""
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization'
    return response


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint."""
    return {'status': 'healthy'}


async def _handle_foo_bar_async(message: str) -> str:
    """Async handler for foo/bar endpoint."""
    # Verify access request
    request_payload, token, nonce = await server_instance.verifier.verify(message)

    # Check if device is revoked
    is_revoked = await server_instance.revoked_devices_client.exists(token.device)
    if is_revoked:
        raise ValueError('device revoked')

    # Check permissions
    permissions_by_role = token.attributes.get('permissionsByRole', {})
    user_permissions = permissions_by_role.get('user', [])

    if not isinstance(user_permissions, list) or 'read' not in user_permissions:
        raise ValueError('unauthorized')

    # Get server identity
    server_identity = await server_instance.response_key.identity()

    # Create response payload
    response_payload = {
        'wasFoo': request_payload['foo'],
        'wasBar': request_payload['bar'],
        'serverName': 'python'
    }

    # Create and sign server response
    response = ServerResponse(response_payload, server_identity, nonce)
    await response.sign(server_instance.response_key)
    return await response.serialize()


@app.route('/foo/bar', methods=['POST'])
def foo_bar():
    """Authenticated endpoint that processes foo/bar requests."""
    try:
        # Read request body
        message = request.data.decode('utf-8')

        # Run async handler in the background event loop
        reply = run_async(_handle_foo_bar_async(message))
        return Response(reply, content_type='application/json')

    except ValueError as e:
        if str(e) == 'unauthorized':
            return {'error': 'unauthorized'}, 401
        if str(e) == 'device revoked':
            return {'error': 'device revoked'}, 403
        raise
    except Exception as e:
        logger.error(f"Error handling request: {e}", exc_info=True)
        return {'error': 'internal server error'}, 500


@app.route('/', defaults={'path': ''})
@app.route('/<path:path>')
def catch_all(path):
    """Catch-all route for 404s."""
    return {'error': 'not found'}, 404


def signal_handler(sig, frame):
    """Handle shutdown signals."""
    global _loop
    logger.info("Shutdown signal received, cleaning up...")
    if _loop:
        asyncio.run_coroutine_threadsafe(server_instance.cleanup(), _loop).result()
        _loop.call_soon_threadsafe(_loop.stop)
    sys.exit(0)


def main():
    """Main entry point."""
    global _loop, _loop_thread

    # Create and start event loop in a background thread
    _loop = asyncio.new_event_loop()
    _loop_thread = threading.Thread(target=_run_event_loop, args=(_loop,), daemon=True)
    _loop_thread.start()

    # Initialize server in the background event loop
    future = asyncio.run_coroutine_threadsafe(server_instance.initialize(), _loop)
    future.result()

    # Register signal handlers
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    # Start Flask server
    port = 80
    logger.info(f"Application server running on port {port}")
    app.run(host='0.0.0.0', port=port, debug=False)


if __name__ == '__main__':
    main()
