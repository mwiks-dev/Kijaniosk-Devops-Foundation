# IAM Least Privilege Design

## Use case
This IAM policy is for the **KijaniKiosk application backend** that uploads product images and receipt files to a storage bucket.

The application should be able to:
- upload files
- read files it uploaded
- list the specific bucket for application operations

It should **not** be able to:
- delete the bucket
- manage IAM
- access unrelated buckets
- administer other cloud services

## Least privilege principle
Least privilege means giving the application only the permissions required to perform its job and nothing more.
