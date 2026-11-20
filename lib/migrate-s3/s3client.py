"""Shared boto3 client + helpers for the toolkit's S3 (SeaweedFS) plane.
Requires S3_ENDPOINT in the environment; AWS keys from the environment
(set by the toolkit from config/variables.env)."""
import os

import boto3
import botocore.client


def client():
    return boto3.client(
        "s3",
        endpoint_url=os.environ["S3_ENDPOINT"].rstrip("/"),
        aws_access_key_id=os.environ.get("AWS_ACCESS_KEY_ID") or "x",
        aws_secret_access_key=os.environ.get("AWS_SECRET_ACCESS_KEY") or "x",
        config=botocore.client.Config(
            s3={"addressing_style": "path"}, signature_version="s3v4"
        ),
        region_name="us-east-1",
    )


def list_all(s3, bucket):
    """Yield every object metadata dict in the bucket (paged)."""
    p = {}
    while True:
        p = s3.list_objects_v2(
            Bucket=bucket,
            **({"ContinuationToken": p["NextContinuationToken"]} if p.get("NextContinuationToken") else {}),
        )
        yield from p.get("Contents", [])
        if not p.get("IsTruncated"):
            break
