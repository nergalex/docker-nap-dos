#!/bin/bash

if [[ $# -lt 2 ]]; then
  echo "Error: Missing required argument"
  echo "export KEY_ID=XXX"
  echo "export SEC_KEY=XXX"
  echo "export SESS_TOKEN=XXX"
  echo "Usage: get-object-s3.sh bucket_name object_path"
  exit 1
fi

# Retreive AWS Region name where the instance is launched
REGION="eu-west-3"
AWS_SERVICE="s3"

HTTP_METHOD="GET"
CANONICAL_URI="/$2"

#Retreive current date in appropriate format
DATE_AND_TIME=$(date -u +"%Y%m%dT%H%M%SZ")
DATE=$(date -u +"%Y%m%d")
EMPTY_STRING_HASH=$(printf "" | openssl dgst -sha256 | cut -d ' ' -f 2)

#Store Canonical request
/bin/cat >./canonical_request.tmp <<EOF
$HTTP_METHOD
$CANONICAL_URI

host:$1.s3.amazonaws.com
x-amz-content-sha256:$EMPTY_STRING_HASH
x-amz-date:$DATE_AND_TIME
x-amz-security-token:$SESS_TOKEN

host;x-amz-content-sha256;x-amz-date;x-amz-security-token
$EMPTY_STRING_HASH
EOF

# Remove trailing newline
printf %s "$(cat canonical_request.tmp)" > canonical_request.tmp

# Generate canonical request hash
CANONICAL_REQUEST_HASH=$(openssl dgst -sha256 canonical_request.tmp | awk -F ' ' '{print $2}')

# Function to generate sha256 hash
function hmac_sha256 {
  key="$1"
  data="$2"
  echo -n "$data" | openssl dgst -sha256 -mac HMAC -macopt "$key" | sed 's/^.* //'
}

# Compute signing key
DATE_KEY=$(hmac_sha256 key:"AWS4$SEC_KEY" $DATE)
DATE_REGION_KEY=$(hmac_sha256 hexkey:$DATE_KEY $REGION)
DATE_REGION_SERVICE_KEY=$(hmac_sha256 hexkey:$DATE_REGION_KEY $AWS_SERVICE)
HEX_KEY=$(hmac_sha256 hexkey:$DATE_REGION_SERVICE_KEY "aws4_request")

# Store string to sign
/bin/cat >./string_to_sign.tmp <<EOF
AWS4-HMAC-SHA256
$DATE_AND_TIME
$DATE/$REGION/$AWS_SERVICE/aws4_request
$CANONICAL_REQUEST_HASH
EOF

printf %s "$(cat string_to_sign.tmp)" > string_to_sign.tmp

# Generate signature
SIGNATURE=$(openssl dgst -sha256 -mac HMAC -macopt hexkey:$HEX_KEY string_to_sign.tmp | awk -F ' ' '{print $2}')

# Remove temporary files
rm canonical_request.tmp string_to_sign.tmp

# Remove file prefix
OUTPUT=$(echo $2 |  awk -F '/' '{print $NF}')

# HTTP Request using signature
curl -s https://$1.s3.amazonaws.com/$2 \
  -X $HTTP_METHOD \
  -H "Authorization: AWS4-HMAC-SHA256 \
      Credential=$KEY_ID/$DATE/$REGION/$AWS_SERVICE/aws4_request, \
      SignedHeaders=host;x-amz-content-sha256;x-amz-date;x-amz-security-token, \
      Signature=$SIGNATURE" \
  -H "x-amz-content-sha256: $EMPTY_STRING_HASH" \
  -H "x-amz-date: $DATE_AND_TIME" \
  -H "x-amz-security-token: $SESS_TOKEN" \
  -o "$OUTPUT"
