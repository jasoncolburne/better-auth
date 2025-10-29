"""HSM KeyVerifier with caching and 12-hour expiry."""

import json
import logging
import os
import sys
from datetime import datetime, timedelta
from typing import Dict, Optional

import redis.asyncio as aioredis

# Add the better-auth-py implementation to the path
if os.path.exists('/dependencies/better-auth-py'):
    better_auth_path = '/dependencies/better-auth-py'
    examples_path = '/dependencies/better-auth-py/examples'
else:
    better_auth_path = os.path.join(os.path.dirname(__file__), '../../../../implementations/better-auth-py')
    examples_path = os.path.join(os.path.dirname(__file__), '../../../../implementations/better-auth-py/examples')

sys.path.insert(0, better_auth_path)
sys.path.insert(0, examples_path)

from implementation.crypto.secp256r1 import Secp256r1Verifier
from implementation.crypto.hash import Hasher
from utils import get_sub_json

HSM_IDENTITY = "BETTER_AUTH_HSM_IDENTITY_PLACEHOLDER"
TWELVE_HOURS_FIFTEEN_MINUTES = timedelta(hours=12, minutes=15)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s: %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

class LogEntry:
    """HSM key log entry."""
    def __init__(self, data: Dict):
        self.id = data['id']
        self.prefix = data['prefix']
        self.previous = data.get('previous')
        self.sequence_number = data['sequenceNumber']
        self.created_at = datetime.fromisoformat(data['createdAt'].replace('Z', '+00:00'))
        self.purpose = data['purpose']
        self.public_key = data['publicKey']
        self.rotation_hash = data['rotationHash']


class SignedLogEntry:
    """Signed HSM key log entry."""
    def __init__(self, data: Dict):
        self.payload = LogEntry(data['payload'])
        self.signature = data['signature']


class KeyVerifier:
    """Verifies HSM signatures with caching and 12-hour expiry."""

    def __init__(self, redis_host: str, redis_db_hsm_keys: int):
        self.redis_client = aioredis.from_url(
            f"redis://{redis_host}/{redis_db_hsm_keys}",
            encoding="utf-8",
            decode_responses=True
        )
        self.verifier = Secp256r1Verifier()
        self.hasher = Hasher()
        self.cache: Dict[str, LogEntry] = {}

    async def verify(
        self,
        signature: str,
        hsm_identity: str,
        hsm_generation_id: str,
        message: str
    ) -> None:
        """Verify a signature using HSM keys from Redis."""
        cached_entry = self.cache.get(hsm_generation_id)

        if not cached_entry:
            # Fetch all HSM keys from Redis
            keys = await self.redis_client.keys('*')
            if not keys:
                raise ValueError("No HSM keys found in Redis")

            values = await self.redis_client.mget(keys)

            # Group by prefix
            by_prefix: Dict[str, list[tuple[SignedLogEntry, str]]] = {}

            for value in values:
                if not value:
                    continue

                payload_json = get_sub_json(value, "payload")
                record = SignedLogEntry(json.loads(value))

                prefix = record.payload.prefix

                if prefix not in by_prefix:
                    by_prefix[prefix] = []

                by_prefix[prefix].append((record, payload_json))

            # Sort by sequence number
            for prefix in by_prefix:
                by_prefix[prefix].sort(key=lambda r: r[0].payload.sequence_number)

            # Verify data & signatures for all records
            for prefix in by_prefix:
                records = by_prefix[prefix]

                for record, payload_json in records:
                    payload = record.payload

                    if payload.sequence_number == 0:
                        await self._verify_prefix_and_data(payload_json, payload)
                    else:
                        await self._verify_address_and_data(payload_json, payload)

                    await self.verifier.verify(payload_json, record.signature, payload.public_key)

            # Verify chains
            for records in by_prefix.values():
                last_id = ''
                last_rotation_hash = ''

                for i, (record, _) in enumerate(records):
                    payload = record.payload

                    if payload.sequence_number != i:
                        raise ValueError('bad sequence number')

                    if payload.sequence_number != 0:
                        if last_id != payload.previous:
                            raise ValueError('broken chain')

                        hash = await self.hasher.sum(payload.public_key)

                        if hash != last_rotation_hash:
                            raise ValueError('bad commitment')

                    last_id = payload.id
                    last_rotation_hash = payload.rotation_hash

            # Verify prefix exists
            if HSM_IDENTITY not in by_prefix:
                raise ValueError('hsm identity not found')

            records = by_prefix[HSM_IDENTITY]

            # Cache entries within 12-hour window (iterate backwards)
            for record, _ in reversed(records):
                payload = record.payload
                self.cache[payload.id] = payload

                if payload.created_at + TWELVE_HOURS_FIFTEEN_MINUTES < datetime.now(payload.created_at.tzinfo):
                    break

            cached_entry = self.cache.get(hsm_generation_id)
            if not cached_entry:
                raise ValueError("can't find valid public key")

        if cached_entry.prefix != hsm_identity:
            raise ValueError('incorrect identity (expected hsm.identity == prefix)')

        if cached_entry.purpose != 'key-authorization':
            raise ValueError('incorrect purpose (expected key-authorization)')

        # Verify message signature
        await self.verifier.verify(message, signature, cached_entry.public_key)

    async def _verify_prefix_and_data(self, payload_json: str, payload: LogEntry) -> None:
        """Verify prefix and data for sequence 0."""
        if payload.id != payload.prefix:
            raise ValueError('prefix must equal id for sequence 0')

        await self._verify_address_and_data(payload_json, payload)

    async def _verify_address_and_data(self, payload_json: str, payload: LogEntry) -> None:
        """Verify address and data."""
        modified_payload = payload_json.replace(payload.id, '############################################')

        hash = await self.hasher.sum(modified_payload)

        if hash != payload.id:
            raise ValueError("id does not match")

    async def close(self) -> None:
        """Close Redis connection."""
        await self.redis_client.aclose()
