#!/bin/bash
set -e

# Load env if needed
if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

# Kiểm tra biến môi trường cần thiết
: "${AWS_RDS_ENDPOINT:?Need to set AWS_RDS_ENDPOINT}"
: "${AWS_RDS_USER:?Need to set AWS_RDS_USER}"
: "${AWS_RDS_PASSWORD:?Need to set AWS_RDS_PASSWORD}"
: "${AWS_RDS_DBNAME:?Need to set AWS_RDS_DBNAME}"
: "${S3_BUCKET_NAME:?Need to set S3_BUCKET_NAME}"
: "${AWS_REGION:?Need to set AWS_REGION}"

# Insert dummy data
DUMMY_ID=$(( RANDOM % 100000 ))
DUMMY_NAME="Test User $DUMMY_ID"
DUMMY_EMAIL="test$DUMMY_ID@example.com"
DUMMY_PHONE="0123456789"
DUMMY_ADDRESS="123 Test St, Test City"
DUMMY_CREATED_AT=$(date '+%Y-%m-%d %H:%M:%S')
DUMMY_UPDATED_AT=$DUMMY_CREATED_AT

SQL="INSERT INTO public.customers (id, name, email, phone, address, created_at, updated_at) VALUES ($DUMMY_ID, '$DUMMY_NAME', '$DUMMY_EMAIL', '$DUMMY_PHONE', '$DUMMY_ADDRESS', '$DUMMY_CREATED_AT', '$DUMMY_UPDATED_AT');"

echo "Inserting dummy row into PostgreSQL..."
PGPASSWORD="$AWS_RDS_PASSWORD" psql -h "$AWS_RDS_ENDPOINT" -U "$AWS_RDS_USER" -d "$AWS_RDS_DBNAME" -c "$SQL"

echo "Waiting for CDC pipeline to process (20s)..."
sleep 20

echo "Checking latest file in S3 bucket: $S3_BUCKET_NAME"
LATEST_FILE=$(aws s3api list-objects-v2 --bucket "$S3_BUCKET_NAME" --query 'Contents | sort_by(@, &LastModified)[-1].Key' --output text --region "$AWS_REGION")

if [ -z "$LATEST_FILE" ]; then
  echo "[ERROR] No file found in S3 bucket. CDC may not be working."
  exit 1
fi

echo "Latest file in S3: $LATEST_FILE"
echo "Downloading and showing content:"
aws s3 cp "s3://$S3_BUCKET_NAME/$LATEST_FILE" - --region "$AWS_REGION" | head -20

echo "[SUCCESS] CDC test completed. Check above for inserted data."